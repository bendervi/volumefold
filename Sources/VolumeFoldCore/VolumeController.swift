import Foundation
import Combine

/// Main-thread state machine. The hardware drivers never touch volume policy.
public final class VolumeController: ObservableObject {
    @Published public private(set) var enabled = false
    @Published public private(set) var angle: Double?
    @Published public private(set) var output: AudioOutput?
    @Published public private(set) var status = "VolumeFold is off"
    @Published public private(set) var deadpoint: Double
    public private(set) var normalVolume: Double?

    private let sensor: LidSensor
    private let audio: AudioDevice
    private let scheduler: ControlScheduler
    private var sleeping = false
    private var started = false
    private var baselineID: UInt32?
    private var observedVolume: Double?
    private var pendingManualVolume: Double?
    private var ramp: Cancellation?
    private var rampStart = 0.0
    private var rampFrom = 0.0
    private var target = 0.0
    private var inFlightVolume: Double?

    public init(sensor: LidSensor, audio: AudioDevice, scheduler: ControlScheduler = MainRunLoopScheduler(), deadpoint: Double = 80) {
        self.sensor = sensor
        self.audio = audio
        self.scheduler = scheduler
        self.deadpoint = deadpoint.isFinite ? min(120, max(10, deadpoint)) : 80
        sensor.onReading = { [weak self] in self?.receiveAngle($0) }
        audio.onChange = { [weak self] in self?.audioChanged() }
    }

    public func start(enabled: Bool) {
        guard !started else { return }
        started = true
        audio.start()
        output = audio.currentOutput()
        setEnabled(enabled)
    }

    public func setEnabled(_ value: Bool) {
        enabled = value
        stopRamp()
        sensor.stop()
        angle = nil
        resetBaseline()
        output = audio.currentOutput()
        if value && !sleeping {
            captureBaseline()
            sensor.start()
        }
        updateStatus()
    }

    public func setDeadpoint(_ value: Double) {
        guard value.isFinite else { return }
        deadpoint = min(120, max(10, value.rounded()))
        updateTarget()
    }

    public func sleep() {
        sleeping = true
        stopRamp()
        sensor.stop()
        angle = nil
        updateStatus()
    }

    public func wake() {
        sleeping = false
        angle = nil
        audioChanged()
        if enabled { sensor.start() }
        updateStatus()
    }

    public func shutdown() {
        enabled = false
        stopRamp()
        sensor.stop()
        audio.stop()
        started = false
    }

    private func receiveAngle(_ reading: Double?) {
        guard enabled, !sleeping else { return }
        guard let reading, reading.isFinite, (0...180).contains(reading) else {
            angle = nil
            stopRamp()
            updateStatus()
            return
        }
        if angle != reading { angle = reading }
        updateStatus()
        updateTarget()
    }

    private func audioChanged() {
        let previous = output
        output = audio.currentOutput()
        guard enabled else { updateStatus(); return }
        if previous?.id != output?.id || previous?.canControl != output?.canControl {
            stopRamp()
            resetBaseline()
            captureBaseline()
            // A new output needs a fresh sensor sample, never the previous route's angle.
            angle = nil
        } else if baselineID == nil {
            captureBaseline()
        } else if let current = output, current.canControl, let volume = current.volume {
            let ownWrite = inFlightVolume.map { abs($0 - volume) < 0.004 } ?? false
            if let observedVolume, abs(volume - observedVolume) >= 0.004, !ownWrite {
                stopRamp()
                inFlightVolume = nil
                if let angle, !sleeping,
                   let normal = FoldCurve.normalVolume(audible: volume, multiplier: multiplier(angle)) {
                    normalVolume = normal
                    pendingManualVolume = nil
                } else {
                    pendingManualVolume = volume
                }
            }
            observedVolume = volume
        }
        updateStatus()
        // Leave manual changes audible until the next angle sample.
    }

    private func captureBaseline() {
        guard let output, output.canControl, let volume = output.volume else { return }
        baselineID = output.id
        normalVolume = volume
        observedVolume = volume
    }

    private func resetBaseline() {
        baselineID = nil
        normalVolume = nil
        observedVolume = nil
        pendingManualVolume = nil
        inFlightVolume = nil
    }

    private func multiplier(_ angle: Double) -> Double {
        FoldCurve.multiplier(angle: angle, deadpoint: deadpoint)
    }

    private func updateTarget() {
        guard enabled, !sleeping, let angle, let output, output.canControl,
              baselineID == output.id, let current = output.volume else { return }
        let factor = multiplier(angle)
        if let pending = pendingManualVolume {
            guard let normal = FoldCurve.normalVolume(audible: pending, multiplier: factor) else { return }
            normalVolume = normal
            pendingManualVolume = nil
        }
        guard let normalVolume else { return }
        let next = normalVolume * factor
        if ramp != nil && abs(next - target) < 0.001 { return }
        guard abs(next - current) >= 0.003 || (next == 0 && current > 0) else {
            stopRamp()
            return
        }
        stopRamp()
        target = next
        rampFrom = current
        rampStart = scheduler.now
        ramp = scheduler.repeating(every: 0.05) { [weak self] in self?.stepRamp() }
    }

    private func stepRamp() {
        guard enabled, !sleeping, angle != nil, let output, output.canControl,
              let id = baselineID, id == output.id else { stopRamp(); return }
        // Recheck immediately before writing, including manual changes whose listener is pending.
        let fresh = audio.currentOutput()
        if fresh != output {
            audioChanged()
            return
        }
        let progress = min(1, max(0, (scheduler.now - rampStart) / 0.15))
        let value = rampFrom + (target - rampFrom) * progress
        do {
            inFlightVolume = value
            try audio.setVolume(value, outputID: id)
            // Read back hardware quantization; record it as our own write as well.
            if let actual = audio.currentOutput(), actual.id == id {
                self.output = actual
                if let volume = actual.volume {
                    observedVolume = volume
                }
            }
            inFlightVolume = nil
        } catch {
            inFlightVolume = nil
            stopRamp()
            // Do not retry writes until an audio-device event establishes a fresh baseline.
            resetBaseline()
            status = "Couldn’t adjust speaker volume"
            return
        }
        if progress >= 1 { stopRamp() }
    }

    private func stopRamp() { ramp?.cancel(); ramp = nil }

    private func updateStatus() {
        let next: String
        if !enabled { next = "VolumeFold is off" }
        else if sleeping { next = "Paused while Mac sleeps" }
        else if output == nil { next = "No audio output available" }
        else if output?.isBuiltInSpeaker == false { next = "Paused · using \(output?.name ?? "external audio")" }
        else if output?.canControl == false { next = "Speaker volume control unavailable" }
        else if baselineID == nil { next = "Couldn’t adjust speaker volume" }
        else if angle == nil { next = "Hinge sensor unavailable · retrying" }
        else if output?.isMuted == true { next = "Speakers muted" }
        else if let angle, angle < deadpoint { next = "Fading with your lid" }
        else { next = "Above deadpoint · normal volume" }
        if status != next { status = next }
    }
}
