import SwiftUI
import AppKit
import Combine

@main
struct VolumeFoldApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private var controller: VolumeController!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var observation: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.volumefold.VolumeFold").count <= 1 else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        controller = VolumeController(sensor: HIDLidSensor(), audio: CoreAudioDevice(), deadpoint: settings.deadpoint)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "VolumeFold")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover)
            button.toolTip = "VolumeFold · volume follows your lid"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        observation = controller.objectWillChange
            .merge(with: settings.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateStatusItem() }
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: VolumeFoldMenu(controller: controller, settings: settings))
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller.sleep()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller.wake()
        })
        controller.start(enabled: settings.enabled)
        updateStatusItem()
        if !UserDefaults.standard.bool(forKey: "hasShownControls") {
            UserDefaults.standard.set(true, forKey: "hasShownControls")
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.alphaValue = controller.enabled ? 1 : 0.4
        if controller.enabled, controller.angle != nil,
           let output = controller.output, output.canControl, let volume = output.volume {
            let level = output.isMuted ? "Muted" : "\(Int((volume * 100).rounded()))%"
            button.title = settings.showMenuBarPercentage ? " \(level)" : ""
            button.toolTip = "VolumeFold · \(level) volume · \(controller.status)"
            button.setAccessibilityLabel("VolumeFold, volume \(level), \(controller.status)")
        } else {
            button.title = ""
            button.toolTip = "VolumeFold · \(controller.status)"
            button.setAccessibilityLabel("VolumeFold, \(controller.status)")
        }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        settings.refreshLoginStatus()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
