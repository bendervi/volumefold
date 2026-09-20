import Foundation
import IOKit.hid
#if SWIFT_PACKAGE
import VolumeFoldCore
#endif

public enum HingeReport {
    public static func decode(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3, bytes[0] == 1 else { return nil }
        let degrees = Int(bytes[1]) | (Int(bytes[2]) << 8)
        return (0...180).contains(degrees) ? Double(degrees) : nil
    }
}

/// All HID calls stay on one utility queue. Main-queue generations discard stale callbacks.
public final class HIDLidSensor: LidSensor {
    public var onReading: ((Double?) -> Void)?
    private let queue = DispatchQueue(label: "app.volumefold.hinge", qos: .utility)
    private var generation = 0
    private var timer: DispatchSourceTimer?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var lastDiscovery = -Double.infinity
    private var previousAvailability: Bool?

    public init() {}

    public func start() {
        generation += 1
        let token = generation
        queue.async { [weak self] in
            guard let self else { return }
            self.close()
            self.lastDiscovery = -.infinity
            self.previousAvailability = nil
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(15))
            timer.setEventHandler { [weak self] in self?.sample(generation: token) }
            self.timer = timer
            timer.resume()
        }
    }

    public func stop() {
        generation += 1
        queue.async { [weak self] in self?.close() }
    }

    private func sample(generation token: Int) {
        if device == nil {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastDiscovery >= 2 {
                lastDiscovery = now
                discover()
            }
        }
        var result: Double?
        if let device {
            var bytes = [UInt8](repeating: 0, count: 8)
            var size = bytes.count
            let status = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &size)
            if status == kIOReturnSuccess { result = HingeReport.decode(Array(bytes.prefix(size))) }
            if result == nil { closeDevice() }
        }
        let available = result != nil
        if previousAvailability != available {
            // Retry absent hardware at 0.5 Hz instead of waking at the active sample rate.
            timer?.schedule(deadline: .now() + (available ? 0.1 : 2),
                            repeating: available ? .milliseconds(100) : .seconds(2),
                            leeway: available ? .milliseconds(15) : .milliseconds(200))
            previousAvailability = available
        }
        let reading = result
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.onReading?(reading)
        }
    }

    private func discover() {
        closeDevice()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A
        ] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { continue }
            var buffer = [UInt8](repeating: 0, count: 8)
            var length = buffer.count
            let status = IOHIDDeviceGetReport(candidate, kIOHIDReportTypeFeature, 1, &buffer, &length)
            if status == kIOReturnSuccess, HingeReport.decode(Array(buffer.prefix(length))) != nil {
                device = candidate
                return
            }
            IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    private func closeDevice() {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        manager = nil
    }

    private func close() {
        timer?.cancel()
        timer = nil
        closeDevice()
    }
}
