import Foundation
import Combine
import ServiceManagement

final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var deadpoint: Double { didSet { defaults.set(deadpoint, forKey: "deadpoint") } }
    @Published var showMenuBarPercentage: Bool { didSet { defaults.set(showMenuBarPercentage, forKey: "showMenuBarPercentage") } }
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var loginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["enabled": true, "deadpoint": 80.0, "showMenuBarPercentage": true])
        enabled = defaults.bool(forKey: "enabled")
        showMenuBarPercentage = defaults.bool(forKey: "showMenuBarPercentage")
        let stored = defaults.double(forKey: "deadpoint")
        deadpoint = stored.isFinite ? min(120, max(10, stored)) : 80
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLoginEnabled(_ enabled: Bool) {
        loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginError = "Couldn’t update launch at login. Move VolumeFold to Applications and try again."
        }
        refreshLoginStatus()
    }
}
