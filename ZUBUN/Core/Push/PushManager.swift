//
//  PushManager.swift
//  ZUBUN
//
//  APNs foundation (spec §6/§7): request notification permission at a sensible
//  moment, register for remote notifications, and capture the device token.
//
//  ⚠️ Requires the Push Notifications capability + an APNs key in the Apple
//  Developer account. Sending the token to the backend needs a token-registration
//  endpoint (not in the current contract) — wired as a TODO below.
//

import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class PushManager {
    static let shared = PushManager()
    private init() {}

    private(set) var deviceToken: String?
    private var didRequest = false

    /// Ask once per launch, only after the user is signed into a role.
    func requestAuthorizationIfNeeded() async {
        guard !didRequest else { return }
        didRequest = true
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { registerForRemoteNotifications() }
    }

    func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        // TODO: POST the token to a backend registration endpoint once available,
        // scoped to the current role/session, so the server can target this device.
    }
}
