import Foundation
import ServiceManagement

enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true,  .enabled):       return
        case (false, .notRegistered): return
        case (true,  _):              try service.register()
        case (false, _):              try service.unregister()
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:          return "enabled"
        case .notRegistered:    return "not registered"
        case .requiresApproval: return "requires approval in System Settings → General → Login Items"
        case .notFound:         return "not found"
        @unknown default:       return "unknown"
        }
    }
}
