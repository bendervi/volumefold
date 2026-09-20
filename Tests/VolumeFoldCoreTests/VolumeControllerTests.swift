import XCTest
@testable import VolumeFoldCore
import VolumeFoldHardware

final class FakeSensor: LidSensor {
    var onReading: ((Double?) -> Void)?
    var running = false
    var starts = 0
    func start() { running = true; starts += 1 }
    func stop() { running = false }
    func send(_ value: Double?) { onReading?(value) }
}

final class FakeAudio: AudioDevice {
    var onChange: (() -> Void)?
    var output: AudioOutput? = AudioOutput(id: 1, name: "Speakers", isBuiltInSpeaker: true, volume: 0.8, isMuted: false)
    var writes: [(UInt32, Double)] = []
    var failWrites = false
    func start() {}
    func stop() {}
    func currentOutput() -> AudioOutput? { output }
    func setVolume(_ volume: Double, outputID: UInt32) throws {
        if failWrites { throw AudioControlError.writeFailed(-1) }
        guard let output, output.id == outputID, output.isBuiltInSpeaker else { throw AudioControlError.routeChanged }
        writes.append((outputID, volume))
        self.output = AudioOutput(id: output.id, name: output.name, isBuiltInSpeaker: true, volume: volume, isMuted: output.isMuted)
        onChange?() // Also exercise a driver that delivers its own callbacks synchronously.
    }
    func change(id: UInt32 = 1, speaker: Bool = true, volume: Double? = 0.8, muted: Bool = false, notify: Bool = true) {
        output = AudioOutput(id: id, name: speaker ? "Speakers" : "Headphones", isBuiltInSpeaker: speaker, volume: volume, isMuted: muted)
        if notify { onChange?() }
    }
}

final class FakeScheduler: ControlScheduler {
    final class Job: Cancellation {
        var active = true
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        func cancel() { active = false }
    }
    var now = 0.0
    var jobs: [Job] = []
    func repeating(every interval: TimeInterval, action: @escaping () -> Void) -> Cancellation {
        let job = Job(action)
        jobs.append(job)
        return job
    }
    func advance(_ seconds: Double = 0.25) {
        let ticks = Int((seconds / 0.05).rounded())
        for _ in 0..<max(0, ticks) {
            now += 0.05
            let current = jobs.filter(\.active)
            for job in current where job.active { job.action() }
            jobs.removeAll { !$0.active }
        }
    }
}

final class VolumeControllerTests: XCTestCase {
    private var sensor: FakeSensor!
    private var audio: FakeAudio!
    private var clock: FakeScheduler!
    private var controller: VolumeController!

    override func setUp() {
        sensor = FakeSensor(); audio = FakeAudio(); clock = FakeScheduler()
        controller = VolumeController(sensor: sensor, audio: audio, scheduler: clock)
        controller.start(enabled: true)
    }

    func testCurveBoundariesAndClamping() {
        XCTAssertEqual(FoldCurve.multiplier(angle: 0, deadpoint: 80), 0)
        XCTAssertEqual(FoldCurve.multiplier(angle: 5, deadpoint: 80), 0)
        XCTAssertEqual(FoldCurve.multiplier(angle: 42.5, deadpoint: 80), 0.5)
        XCTAssertEqual(FoldCurve.multiplier(angle: 80, deadpoint: 80), 1)
        XCTAssertEqual(FoldCurve.multiplier(angle: 140, deadpoint: 80), 1)
        XCTAssertEqual(FoldCurve.multiplier(angle: 7.5, deadpoint: 10), 0.5)
        XCTAssertEqual(FoldCurve.multiplier(angle: 62.5, deadpoint: 120), 0.5)
        XCTAssertNil(FoldCurve.normalVolume(audible: 0.5, multiplier: 0))
        XCTAssertEqual(FoldCurve.normalVolume(audible: 0.8, multiplier: 0.5), 1)
    }

    func testFadesSmoothlyAndRestoresWithoutCompounding() {
        sensor.send(42.5)
        XCTAssertEqual(audio.writes.count, 0)
        clock.advance(0.05)
        XCTAssertGreaterThan(audio.output!.volume!, 0.4)
        XCTAssertLessThan(audio.output!.volume!, 0.8)
        clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.4, accuracy: 0.001)
        XCTAssertEqual(controller.normalVolume!, 0.8, accuracy: 0.001)
        sensor.send(80); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.8, accuracy: 0.001)
    }

    func testStationaryReadingsDoNotWriteOrKeepTimerAlive() {
        sensor.send(110); clock.advance()
        XCTAssertTrue(audio.writes.isEmpty)
        sensor.send(42.5); clock.advance()
        let count = audio.writes.count
        for _ in 0..<100 { sensor.send(42.5); clock.advance(0.1) }
        XCTAssertEqual(audio.writes.count, count)
        XCTAssertTrue(clock.jobs.isEmpty)
    }

    func testDisableAndQuitLeaveCurrentVolumeAndStopPolling() {
        sensor.send(42.5); clock.advance()
        controller.setEnabled(false)
        XCTAssertFalse(sensor.running)
        sensor.send(120); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.4, accuracy: 0.001)
        controller.setEnabled(true)
        XCTAssertEqual(controller.normalVolume!, 0.4, accuracy: 0.001)
        sensor.send(5); clock.advance(0.05)
        let beforeQuit = audio.output!.volume!
        controller.shutdown(); clock.advance()
        XCTAssertEqual(audio.output!.volume!, beforeQuit)
        XCTAssertFalse(sensor.running)
    }

    func testManualChangeUpdatesRestoredLevel() {
        sensor.send(42.5); clock.advance()
        audio.change(volume: 0.3)
        XCTAssertEqual(controller.normalVolume!, 0.6, accuracy: 0.001)
        sensor.send(100); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.6, accuracy: 0.001)
    }

    func testManualChangeToEarlierRampValueIsNotMistakenForOwnWrite() {
        sensor.send(42.5); clock.advance()
        audio.change(volume: 0.8)
        XCTAssertEqual(controller.normalVolume!, 1, accuracy: 0.001)
    }

    func testManualChangeWithDelayedNotificationWinsOverRamp() {
        sensor.send(42.5); clock.advance(0.05)
        audio.change(volume: 0.2, notify: false)
        clock.advance()
        XCTAssertEqual(controller.normalVolume!, 0.4, accuracy: 0.001)
        XCTAssertEqual(audio.output!.volume!, 0.2, accuracy: 0.001)
    }

    func testManualVolumeAtClosedLidIsDeferred() {
        sensor.send(5); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0, accuracy: 0.001)
        audio.change(volume: 0.2)
        sensor.send(0); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.2, accuracy: 0.001)
        sensor.send(42.5); clock.advance()
        XCTAssertEqual(controller.normalVolume!, 0.4, accuracy: 0.001)
        sensor.send(100); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.4, accuracy: 0.001)
    }

    func testExternalAudioAndRouteRaceAreNeverWritten() {
        sensor.send(42.5)
        audio.change(id: 2, speaker: false, volume: 0.7, notify: false)
        clock.advance()
        XCTAssertTrue(audio.writes.isEmpty)
        sensor.send(0); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.7)
        audio.change(volume: 0.6)
        clock.advance()
        XCTAssertTrue(audio.writes.isEmpty, "Wait for a fresh angle on route changes")
        sensor.send(42.5); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.3, accuracy: 0.001)
        XCTAssertEqual(controller.normalVolume!, 0.6, accuracy: 0.001)
    }

    func testSameDeviceJackSwitchPausesControl() {
        sensor.send(42.5)
        audio.change(speaker: false, volume: 0.5)
        clock.advance()
        XCTAssertTrue(audio.writes.isEmpty)
        XCTAssertTrue(controller.status.contains("Headphones"))
    }

    func testSleepWakePreservesBaselineAndRequiresFreshReading() {
        sensor.send(42.5); clock.advance()
        controller.sleep()
        XCTAssertFalse(sensor.running)
        sensor.send(100); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.4, accuracy: 0.001)
        controller.wake(); clock.advance()
        XCTAssertTrue(sensor.running)
        XCTAssertNil(controller.angle)
        XCTAssertEqual(audio.output!.volume!, 0.4, accuracy: 0.001)
        sensor.send(100); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.8, accuracy: 0.001)
    }

    func testWakeWithChangedOutputCapturesNewBaseline() {
        controller.sleep()
        audio.change(id: 3, volume: 0.5, notify: false)
        controller.wake()
        sensor.send(42.5); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.25, accuracy: 0.001)
    }

    func testSensorFailureCancelsRampAndCanRecover() {
        sensor.send(42.5); clock.advance(0.05)
        let held = audio.output!.volume!
        sensor.send(nil); clock.advance()
        XCTAssertEqual(audio.output!.volume!, held)
        XCTAssertTrue(controller.status.contains("unavailable"))
        sensor.send(.nan); clock.advance()
        XCTAssertNil(controller.angle)
        sensor.send(181); XCTAssertNil(controller.angle)
        sensor.send(100); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.8, accuracy: 0.001)
    }

    func testMutedStateIsPreserved() {
        audio.change(muted: true)
        sensor.send(42.5); clock.advance()
        XCTAssertTrue(audio.output!.isMuted)
        XCTAssertEqual(controller.status, "Speakers muted")
        sensor.send(100); clock.advance()
        XCTAssertTrue(audio.output!.isMuted)
    }

    func testDeadpointAppliesImmediatelyAndClamps() {
        sensor.send(80); clock.advance()
        controller.setDeadpoint(120); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.8 * 75 / 115, accuracy: 0.001)
        controller.setDeadpoint(-5)
        XCTAssertEqual(controller.deadpoint, 10)
        controller.setDeadpoint(.nan)
        XCTAssertEqual(controller.deadpoint, 10)
    }

    func testWriteFailureStopsRetriesUntilAudioEvent() {
        audio.failWrites = true
        sensor.send(42.5); clock.advance()
        XCTAssertTrue(controller.status.contains("Couldn’t"))
        sensor.send(100); clock.advance()
        XCTAssertTrue(audio.writes.isEmpty)
        audio.failWrites = false
        audio.change(volume: 0.6)
        sensor.send(42.5); clock.advance()
        XCTAssertEqual(audio.output!.volume!, 0.3, accuracy: 0.001)
    }

    func testUnavailableVolumeDoesNotWrite() {
        audio.change(volume: nil)
        sensor.send(5); clock.advance()
        XCTAssertTrue(audio.writes.isEmpty)
        XCTAssertTrue(controller.status.contains("unavailable"))
    }

    func testHingeReportValidation() {
        XCTAssertEqual(HingeReport.decode([1, 90, 0]), 90)
        XCTAssertEqual(HingeReport.decode([1, 0, 0]), 0)
        XCTAssertNil(HingeReport.decode([1, 90]))
        XCTAssertNil(HingeReport.decode([2, 90, 0]))
        XCTAssertNil(HingeReport.decode([1, 255, 255]))
    }
}
