//
//  AppDelegate.swift
//  ZUBUN
//
//  Minimal app delegate to receive the APNs device token (SwiftUI has no direct
//  hook for this). Wired via @UIApplicationDelegateAdaptor in ZUBUNApp.
//

#if canImport(UIKit)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Non-fatal: push simply won't be available this session.
    }
}
#endif
