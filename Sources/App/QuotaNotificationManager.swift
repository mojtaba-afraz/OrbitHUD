import Foundation
import UserNotifications
#if canImport(AntigravityUsageCore)
import AntigravityUsageCore
#endif

/// Safely delivers native macOS UserNotifications for Smart Quota Alerts.
/// Guards all UNUserNotificationCenter calls so unbundled dev/test binaries never crash.
final class QuotaNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    override init() {
        super.init()
        if isBundledApp {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestAuthorizationIfNeeded() {
        guard isBundledApp else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }
        }
    }

    func deliver(_ events: [QuotaAlertEvent]) {
        guard isBundledApp, !events.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: event.id,
                content: content,
                trigger: nil
            )
            center.add(request) { _ in }
        }
    }

    // Show banners & play sound even when OrbitHUD's popover or floating window is focused
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
