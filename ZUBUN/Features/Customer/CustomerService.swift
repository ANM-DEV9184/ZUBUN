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
        let token = try await supabase.verifyEmailOTP(email: email, code: code)
        session.saveCustomerToken(token)
    }

    func signOut() async {
        await supabase.signOut()
        session.clearCustomer()
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
