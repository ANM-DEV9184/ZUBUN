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

    // MARK: - Auth (phone OTP)

    func sendOTP(phone: String) async throws {
        try await supabase.sendPhoneOTP(phone)
    }

    func verifyOTP(phone: String, code: String) async throws {
        let token = try await supabase.verifyPhoneOTP(phone: phone, code: code)
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

    // MARK: - Actions

    func join(venueID: String, name: String?, marketingOptIn: Bool) async throws -> JoinResult {
        struct Body: Encodable { let venueId: String; let name: String?; let marketingOptIn: Bool }
        return try await api.post("/api/customer/join",
                                  body: Body(venueId: venueID, name: name, marketingOptIn: marketingOptIn),
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
