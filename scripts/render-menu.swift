// Offscreen visual QA. Uses fixtures only; does not access HID or system audio.
import AppKit
import SwiftUI

private final class PreviewSensor: LidSensor {
    var onReading: ((Double?) -> Void)?
    let angle: Double
    init(angle: Double) { self.angle = angle }
    func start() { onReading?(angle) }
    func stop() {}
}

private final class PreviewAudio: AudioDevice {
    var onChange: (() -> Void)?
    private var volume = 0.5
    func start() {}
    func stop() {}
    func currentOutput() -> AudioOutput? {
        AudioOutput(id: 1, name: "MacBook Speakers", isBuiltInSpeaker: true, volume: volume, isMuted: false)
    }
    func setVolume(_ volume: Double, outputID: UInt32) throws { self.volume = volume }
}

@main
enum MenuRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let directory = CommandLine.arguments.dropFirst().first ?? "/tmp/volumefold-preview"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "app.volumefold.visual-qa")!)
        for (state, enabled, angle) in [("enabled", true, 116.0), ("folded", true, 42.5), ("closed", true, 5.0), ("disabled", false, 116.0)] {
            for dark in [false, true] {
                let controller = VolumeController(sensor: PreviewSensor(angle: angle), audio: PreviewAudio())
                controller.start(enabled: enabled)
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                let view = NSHostingView(rootView: VolumeFoldMenu(controller: controller, settings: settings)
                    .environment(\.colorScheme, dark ? .dark : .light))
                view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                view.frame = NSRect(origin: .zero, size: view.fittingSize)
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    fatalError("Could not render menu")
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let name = "\(state)-\(dark ? "dark" : "light").png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
                print("\(name): \(view.frame.size)")
                controller.shutdown()
            }
        }
    }
}
