//
//  CustomerService.swift
//  ZUBUN
//
//  Customer auth (Supabase phone OTP) + the /api/customer/* REST surface
//  (spec §9.3). All data routes send the Supabase access token as a bearer.
//

import Foundation

struct CustomerService {
    var api = APIClient()
    var supabase: SupabaseService = .shared
    var session: SessionStore = .shared

    // MARK: - Auth (email OTP)

    func sendOTP(email: String) async throws {
        try await supabase.sendEmailOTP(email)
    }

    func verifyOTP(email: String, code: String) async throws {
        let tokens = try await supabase.verifyEmailOTP(email: email, code: code)
        session.saveCustomerToken(tokens.accessToken, refresh: tokens.refreshToken)
    }

    /// Refresh the customer access token from the stored refresh token so an
    /// expired JWT doesn't blank the wallet. Runs at customer-app launch. No-op
    /// (returns false) if there's no refresh token yet.
    @discardableResult
    func refreshCustomerSession() async -> Bool {
        guard let refresh = session.customerRefreshToken else { return false }
        do {
            let tokens = try await supabase.refreshSession(refreshToken: refresh)
            session.saveCustomerToken(tokens.accessToken, refresh: tokens.refreshToken ?? refresh)
            return true
        } catch {
            return false
        }
    }

    func signOut() async {
        await supabase.signOut()
        session.clearCustomer()
    }

    /// App-level opt-in for ZUBUN announcements/offers (separate from per-venue marketing).
    func getAnnouncementOptIn() async throws -> Bool {
        struct R: Decodable { let enabled: Bool? }
        let r: R = try await api.get("/api/customer/push-consent", auth: .customer)
        return r.enabled ?? true
    }
    func setAnnouncementOptIn(_ enabled: Bool) async throws {
        struct Body: Encodable { let enabled: Bool }
        struct R: Decodable { let ok: Bool? }
        let _: R = try await api.post("/api/customer/push-consent", body: Body(enabled: enabled), auth: .customer)
    }

    // MARK: - Wallet

    func cards() async throws -> [CustomerCard] {
        let res: CustomerCardsResponse = try await api.get("/api/customer/cards", auth: .customer)
        return res.cards
    }

    func card(membershipID: String) async throws -> CustomerCardDetail {
        try await api.get("/api/customer/card",
                          query: [URLQueryItem(name: "membership_id", value: membershipID)],
                          auth: .customer)
    }

    // MARK: - Notification inbox

    func notifications() async throws -> NotificationsResponse {
        try await api.get("/api/customer/notifications", auth: .customer)
    }

    /// Mark one item read (`id`) or all unread items read (`id == nil`).
    @discardableResult
    func markNotificationRead(id: String?) async throws -> Bool {
        struct Body: Encodable { let id: String? }
        struct OK: Decodable {}
        let _: OK = try await api.post("/api/customer/notifications/read",
                                       body: Body(id: id), auth: .customer)
        return true
    }

    /// DEBUG self-test: push a test notification to this customer's own devices.
    /// Returns per-device APNs status so a bad .p8/env is visible immediately.
    func sendTestPush() async throws -> TestPushResult {
        struct Empty: Encodable {}
        return try await api.post("/api/customer/notifications/test", body: Empty(), auth: .customer)
    }

    // MARK: - Actions

    /// `mobile` is captured for the owner's/venue's reference (offline outreach) —
    /// it is NOT used for auth (auth is the verified email).
    func join(venueID: String, name: String?, mobile: String?, marketingOptIn: Bool) async throws -> JoinResult {
        struct Body: Encodable { let venueId: String; let name: String?; let mobile: String?; let marketingOptIn: Bool }
        return try await api.post("/api/customer/join",
                                  body: Body(venueId: venueID, name: name, mobile: mobile, marketingOptIn: marketingOptIn),
                                  auth: .customer)
    }

    func setBirthday(month: Int, day: Int) async throws -> ResultEnvelope {
        struct Body: Encodable { let month: Int; let day: Int }
        return try await api.postResult("/api/customer/birthday", body: Body(month: month, day: day), auth: .customer)
    }

    func feedback(membershipID: String, score: Int, comment: String?) async throws -> FeedbackResult {
        struct Body: Encodable { let membershipId: String; let score: Int; let comment: String? }
        return try await api.post("/api/customer/feedback",
                                  body: Body(membershipId: membershipID, score: score, comment: comment),
                                  auth: .customer)
    }

    func optOut(membershipID: String?) async throws -> ResultEnvelope {
        struct Body: Encodable { let membershipId: String? }
        return try await api.postResult("/api/customer/opt-out", body: Body(membershipId: membershipID), auth: .customer)
    }

    /// PDPL erasure — satisfies Apple's mandatory in-app account deletion (§6).
    func deleteAccount() async throws -> ResultEnvelope {
        struct Body: Encodable { let action: String }
        return try await api.postResult("/api/customer/account", body: Body(action: "delete"), auth: .customer)
    }
}
