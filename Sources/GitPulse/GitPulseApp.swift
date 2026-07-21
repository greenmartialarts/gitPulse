import SwiftUI
import UserNotifications

@main
struct GitPulseApp: App {
    @StateObject private var model = PulseModel()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        MenuBarExtra("GitPulse", systemImage: model.menuSymbol) {
            PulsePopover(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("GitPulse", id: "dashboard") {
            DashboardView(model: model)
                .frame(minWidth: 760, minHeight: 520)
        }

        Window("GitPulse Settings", id: "settings") {
            SettingsView(model: model)
                .frame(width: 560)
        }
        .windowResizability(.contentSize)
    }
}

final class NotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    nonisolated(unsafe) static let shared = NotificationDelegate()
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, willPresent: UNNotification, withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completion: @escaping () -> Void) {
        if let url = URL(string: response.notification.request.content.userInfo["url"] as? String ?? "") { DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
        completion()
    }
}
