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
        Task { await syncTokenWithBackend() }
    }

    /// Convenience for role Home screens: ask for permission (once) + push the
    /// token to the backend for whatever sessions are active.
    func onActiveSession() async {
        await requestAuthorizationIfNeeded()
        await syncTokenWithBackend()
    }

    /// Registers the current token with the backend for every active role session
    /// (a device may hold more than one). No-op until a token + session exist; the
    /// backend endpoint is defined in docs/PUSH_BACKEND.md.
    func syncTokenWithBackend() async {
        guard let token = deviceToken else { return }
        let session = SessionStore.shared
        let service = PushService()
        if session.staff != nil { await service.register(token: token, role: "staff", auth: .staff) }
        if session.hasCustomerSession { await service.register(token: token, role: "customer", auth: .customer) }
        if session.hasOwnerSession { await service.register(token: token, role: "owner", auth: .owner) }
    }
}
