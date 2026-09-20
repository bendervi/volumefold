import Foundation
import VolumeFoldHardware

// Read-only hardware diagnostic: never calls setVolume or changes preferences.
let audio = CoreAudioDevice()
if let output = audio.currentOutput() {
    print("Output: \(output.name), id: \(output.id), built-in speaker: \(output.isBuiltInSpeaker), volume: \(output.volume.map { String(format: "%.3f", $0) } ?? "unavailable"), muted: \(output.isMuted)")
} else {
    print("No audio output")
}
let sensor = HIDLidSensor()
var count = 0
sensor.onReading = { angle in
    print("Hinge: \(angle.map { String(format: "%.0f°", $0) } ?? "unavailable")")
    count += 1
    if count >= 5 { sensor.stop(); exit(0) }
}
sensor.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 12) { sensor.stop(); exit(1) }
RunLoop.main.run()
