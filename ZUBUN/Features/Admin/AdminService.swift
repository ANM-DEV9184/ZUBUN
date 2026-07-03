//
//  AdminService.swift
//  ZUBUN
//
//  Client for the bearer admin API (/api/admin/app/*). Uses the .owner auth mode
//  since the admin's Supabase token is stored as the owner token.
//

import Foundation

struct AdminService {
    var api = APIClient()

    func overview() async throws -> AdminOverview {
        try await api.get("/api/admin/app/overview", auth: .owner)
    }

    func merchants(q: String = "") async throws -> [AdminMerchant] {
        let query: [URLQueryItem] = q.isEmpty ? [] : [.init(name: "q", value: q)]
        let r: AdminMerchantsResponse = try await api.get("/api/admin/app/merchants", query: query, auth: .owner)
        return r.merchants
    }

    func merchant(id: String) async throws -> AdminMerchantDetail {
        try await api.get("/api/admin/app/merchant", query: [.init(name: "id", value: id)], auth: .owner)
    }

    func updateMerchant(id: String, planTier: String?, billingStatus: String?) async throws {
        struct Body: Encodable { let merchantId: String; let planTier: String?; let billingStatus: String? }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/admin/app/merchant-update",
            body: Body(merchantId: id, planTier: planTier, billingStatus: billingStatus), auth: .owner)
    }

    /// Account controls. Returns an optional URL (reset_password / impersonate).
    @discardableResult
    func account(id: String, action: String, email: String? = nil) async throws -> String? {
        struct Body: Encodable { let merchantId: String; let action: String; let email: String? }
        struct R: Decodable { let url: String? }
        let r: R = try await api.post("/api/admin/app/account",
            body: Body(merchantId: id, action: action, email: email), auth: .owner)
        return r.url
    }

    func impersonate(id: String) async throws -> String? {
        struct Body: Encodable { let merchantId: String }
        struct R: Decodable { let url: String? }
        let r: R = try await api.post("/api/admin/app/impersonate", body: Body(merchantId: id), auth: .owner)
        return r.url
    }

    func venueAction(action: String, venueId: String? = nil, staffId: String? = nil, tokenId: String? = nil) async throws {
        struct Body: Encodable { let action: String; let venueId: String?; let staffId: String?; let tokenId: String? }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/admin/app/venue-action",
            body: Body(action: action, venueId: venueId, staffId: staffId, tokenId: tokenId), auth: .owner)
    }

    func audit() async throws -> [AdminAudit] {
        let r: AdminAuditResponse = try await api.get("/api/admin/app/audit", auth: .owner)
        return r.actions
    }

    func tickets(status: String) async throws -> [AdminTicket] {
        let query: [URLQueryItem] = [.init(name: "status", value: status)]
        let r: AdminTicketsResponse = try await api.get("/api/admin/app/support", query: query, auth: .owner)
        return r.tickets
    }

    func thread(ticketID: String) async throws -> AdminThreadResponse {
        try await api.get("/api/admin/app/support/thread",
                          query: [.init(name: "ticket_id", value: ticketID)], auth: .owner)
    }

    func reply(ticketID: String, body: String) async throws {
        struct Body: Encodable { let ticketId: String; let action: String; let body: String }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/admin/app/support/thread",
            body: Body(ticketId: ticketID, action: "reply", body: body), auth: .owner)
    }

    func note(ticketID: String, body: String) async throws {
        struct Body: Encodable { let ticketId: String; let action: String; let body: String }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/admin/app/support/thread",
            body: Body(ticketId: ticketID, action: "note", body: body), auth: .owner)
    }

    func setStatus(ticketID: String, status: String) async throws {
        struct Body: Encodable { let ticketId: String; let action: String; let status: String }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/admin/app/support/thread",
            body: Body(ticketId: ticketID, action: "status", status: status), auth: .owner)
    }

    // MARK: Troubleshooting (6A)

    func deadJobs() async throws -> [AdminJob] {
        let r: AdminJobsResponse = try await api.get("/api/admin/app/jobs", auth: .owner)
        return r.jobs
    }
    func retryJob(id: String) async throws {
        struct Body: Encodable { let jobId: String }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/admin/app/jobs", body: Body(jobId: id), auth: .owner)
    }
    @discardableResult
    func retryAllJobs() async throws -> Int {
        struct Body: Encodable { let all: Bool }
        struct R: Decodable { let requeued: Int? }
        let r: R = try await api.post("/api/admin/app/jobs", body: Body(all: true), auth: .owner)
        return r.requeued ?? 0
    }
    func failedWebhooks() async throws -> [AdminWebhook] {
        let r: AdminWebhooksResponse = try await api.get("/api/admin/app/webhooks", auth: .owner)
        return r.events
    }
    func replayWebhook(id: String) async throws {
        struct Body: Encodable { let eventId: String }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/admin/app/webhooks", body: Body(eventId: id), auth: .owner)
    }
    func anomalies() async throws -> [AdminSignal] {
        let r: AdminSignalsResponse = try await api.get("/api/admin/app/anomalies", auth: .owner)
        return r.signals
    }

    // MARK: Finance + customers (6C / 6D)

    func finance() async throws -> AdminFinance {
        try await api.get("/api/admin/app/finance", auth: .owner)
    }
    func customerSearch(q: String) async throws -> [AdminCustomerRow] {
        let r: AdminCustomersResponse = try await api.get("/api/admin/app/customers",
                                                          query: [.init(name: "q", value: q)], auth: .owner)
        return r.customers
    }
    func customer(id: String) async throws -> AdminCustomerDetail {
        try await api.get("/api/admin/app/customers", query: [.init(name: "id", value: id)], auth: .owner)
    }
    func voidReward(tokenID: String, venueID: String) async throws {
        try await venueAction(action: "void_reward", venueId: venueID, tokenId: tokenID)
    }
}
