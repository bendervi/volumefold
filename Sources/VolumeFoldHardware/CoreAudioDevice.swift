import Foundation
import CoreAudio
#if SWIFT_PACKAGE
import VolumeFoldCore
#endif

public enum AudioControlError: Error { case routeChanged, volumeUnavailable, writeFailed(OSStatus) }

public final class CoreAudioDevice: AudioDevice {
    public var onChange: (() -> Void)?
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var listeningID: AudioObjectID?
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        listen(system, selector: kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        attachOutputListeners()
    }

    public func stop() {
        for (id, var address, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(id, &address, .main, block)
        }
        listeners.removeAll()
        listeningID = nil
        running = false
    }

    public func currentOutput() -> AudioOutput? {
        guard let id = defaultOutput(), id != kAudioObjectUnknown else { return nil }
        let transport: UInt32? = scalar(id, kAudioDevicePropertyTransportType)
        let isSpeaker = transport == kAudioDeviceTransportTypeBuiltIn && hasSpeakerTerminal(id)
        let elements = volumeElements(id)
        let values: [Double] = elements.compactMap {
            let value: Float32? = scalar(id, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: $0)
            return value.map(Double.init)
        }
        // Highest channel retains headroom and lets proportional writes preserve stereo balance.
        let volume = values.count == elements.count ? values.max() : nil
        let mute: UInt32? = scalar(id, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        return AudioOutput(id: id, name: name(id), isBuiltInSpeaker: isSpeaker,
                           volume: volume, isMuted: mute == 1)
    }

    public func setVolume(_ volume: Double, outputID: UInt32) throws {
        guard volume.isFinite else { throw AudioControlError.volumeUnavailable }
        guard let current = currentOutput(), current.id == outputID, current.isBuiltInSpeaker else {
            throw AudioControlError.routeChanged
        }
        let elements = volumeElements(outputID)
        guard !elements.isEmpty, let oldMax = current.volume else { throw AudioControlError.volumeUnavailable }
        let oldValues: [Float32] = try elements.map { element in
            guard let value: Float32 = scalar(outputID, kAudioDevicePropertyVolumeScalar,
                                              scope: kAudioDevicePropertyScopeOutput, element: element) else {
                throw AudioControlError.volumeUnavailable
            }
            return value
        }
        for (index, element) in elements.enumerated() {
            guard defaultOutput() == outputID, hasSpeakerTerminal(outputID) else { throw AudioControlError.routeChanged }
            let ratio = oldMax > 0 ? Double(oldValues[index]) / oldMax : 1
            var value = Float32(min(1, max(0, volume)) * ratio)
            var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            let result = AudioObjectSetPropertyData(outputID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            guard result == noErr else { throw AudioControlError.writeFailed(result) }
        }
        // Deliberately never write kAudioDevicePropertyMute.
    }

    private func defaultOutput() -> AudioObjectID? { scalar(system, kAudioHardwarePropertyDefaultOutputDevice) }

    private func hasSpeakerTerminal(_ id: AudioObjectID) -> Bool {
        // Older Macs share an output device between the jack and internal speakers.
        let source: UInt32? = scalar(id, kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
        if let source {
            if source == 0x6864706e || source == 0x68647068 { return false } // hdpn / hdph
            if source == 0x6973706b { return true } // ispk: internal speaker
        }
        let streams: [AudioStreamID] = array(id, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        let terminals: [UInt32] = streams.compactMap { scalar($0, kAudioStreamPropertyTerminalType) }
        return !terminals.isEmpty && terminals.allSatisfy { $0 == kAudioStreamTerminalTypeSpeaker }
    }

    private func volumeElements(_ id: AudioObjectID) -> [AudioObjectPropertyElement] {
        if writable(id, element: kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        // Only handle the built-in stereo pair if both channels are independently writable.
        return writable(id, element: 1) && writable(id, element: 2) ? [1, 2] : []
    }

    private func writable(_ id: AudioObjectID, element: AudioObjectPropertyElement) -> Bool {
        var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
        var result: DarwinBoolean = false
        return AudioObjectHasProperty(id, &address)
            && AudioObjectIsPropertySettable(id, &address, &result) == noErr && result.boolValue
    }

    private func name(_ id: AudioObjectID) -> String {
        var address = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return "Audio output" }
        return value?.takeRetainedValue() as String? ?? "Audio output"
    }

    private func attachOutputListeners() {
        let newID = defaultOutput()
        guard newID != listeningID else { return }
        let old = listeners.filter { $0.0 != system }
        for (id, var address, block) in old { AudioObjectRemovePropertyListenerBlock(id, &address, .main, block) }
        listeners.removeAll { $0.0 != system }
        listeningID = newID
        guard let newID else { return }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute,
                         kAudioDevicePropertyDataSource, kAudioDevicePropertyStreams] {
            listen(newID, selector: selector, scope: kAudioDevicePropertyScopeOutput,
                   element: kAudioObjectPropertyElementWildcard)
        }
        let streams: [AudioStreamID] = array(newID, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        for stream in streams { listen(stream, selector: kAudioStreamPropertyTerminalType, scope: kAudioObjectPropertyScopeGlobal) }
    }

    private func listen(_ id: AudioObjectID, selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
        var address = address(selector, scope: scope, element: element)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.running else { return }
            self.attachOutputListeners()
            self.onChange?()
        }
        if AudioObjectAddPropertyListenerBlock(id, &address, .main, block) == noErr {
            listeners.append((id, address, block))
        }
    }

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func scalar<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                           element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var address = address(selector, scope: scope, element: element)
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr,
              size == MemoryLayout<T>.size else { return nil }
        return buffer.load(as: T.self)
    }

    private func array<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope) -> [T] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: buffer.assumingMemoryBound(to: T.self), count: Int(size) / MemoryLayout<T>.size))
    }
}
