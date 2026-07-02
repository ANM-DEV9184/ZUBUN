//
//  AppDelegate.swift
//  ZUBUN
//
//  Minimal app delegate to receive the APNs device token (SwiftUI has no direct
//  hook for this). Wired via @UIApplicationDelegateAdaptor in ZUBUNApp.
//

#if canImport(UIKit)
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Receive taps + foreground presentation for push notifications.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Non-fatal: push simply won't be available this session.
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Tapped a notification (background or foreground) — route to the venue.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        Task { @MainActor in
            PushManager.shared.handleNotificationTap(info)
            completionHandler()
        }
    }

    /// Show the banner even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in await CustomerRouter.shared.refreshUnread() }
        completionHandler([.banner, .sound, .badge])
    }
}
#endif
