//
//  AdminModels.swift
//  ZUBUN
//
//  Super-Admin console models — backed by /api/admin/app/* (bearer, role=admin).
//

import Foundation

struct AdminOverview: Decodable {
    let merchants: Int?
    let venues: Int?
    let members: Int?
    let activeCards: Int?
    let stamps7d: Int?
    let openTickets: Int?
}

struct AdminMerchant: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let planTier: String?
    let billingStatus: String?
    let venueCount: Int?
    let createdAt: String?
}
struct AdminMerchantsResponse: Decodable { let merchants: [AdminMerchant] }

struct AdminMerchantInfo: Decodable, Hashable {
    let id: String
    let name: String?
    let planTier: String?
    let billingStatus: String?
    let ownerContact: String?
    let createdAt: String?
}
struct AdminVenue: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let status: String?
    let vertical: String?
}
struct AdminMerchantDetail: Decodable {
    let merchant: AdminMerchantInfo
    let venues: [AdminVenue]
    let members: Int?
}

struct AdminAudit: Decodable, Identifiable {
    let id: String
    let actor: String?
    let action: String?
    let target: String?
    let createdAt: String?
}
struct AdminAuditResponse: Decodable { let actions: [AdminAudit] }

struct AdminTicket: Decodable, Identifiable, Hashable {
    let id: String
    let subject: String?
    let status: String?
    let category: String?
    let raiserKind: String?
    let raiserLabel: String?
    let raiserTier: String?
    let csatRating: Int?
    let awaiting: Bool?
    let lastMessagePreview: String?
    let lastMessageAt: String?
    let unread: Bool?

    /// e.g. "owner · gold" — who raised it + their tier.
    var raiserBadge: String {
        let kind = (raiserKind ?? "user").capitalized
        if let t = raiserTier, !t.isEmpty { return "\(kind) · \(t)" }
        return kind
    }
}
struct AdminTicketsResponse: Decodable { let tickets: [AdminTicket]; let unreadCount: Int? }

struct AdminThreadMeta: Decodable {
    let id: String
    let subject: String?
    let status: String?
    let raiserKind: String?
    let raiserLabel: String?
    let raiserTier: String?
    let csatRating: Int?
}
struct AdminThreadResponse: Decodable {
    let ticket: AdminThreadMeta
    let messages: [AppTicketMessage]   // reused from the shared support module
}

// MARK: - Troubleshooting (6A)

struct AdminJob: Decodable, Identifiable {
    let id: String
    let jobType: String?
    let attempts: Int?
    let error: String?
    let runAfter: String?
    let createdAt: String?
}
struct AdminJobsResponse: Decodable { let jobs: [AdminJob] }

struct AdminWebhook: Decodable, Identifiable {
    let id: String
    let from: String?
    let error: String?
    let createdAt: String?
}
struct AdminWebhooksResponse: Decodable { let events: [AdminWebhook] }

struct AdminSignal: Decodable, Identifiable {
    let kind: String?
    let title: String?
    let detail: String?
    var id: String { "\(title ?? "")|\(detail ?? "")" }
}
struct AdminSignalsResponse: Decodable { let signals: [AdminSignal] }

/// Plan tiers + billing states an admin can set.
enum AdminPlanTier: String, CaseIterable, Identifiable { case starter, standard, multi; var id: String { rawValue } }
enum AdminBilling: String, CaseIterable, Identifiable {
    case trialing, active, past_due, cancelled
    var id: String { rawValue }
    var label: String { self == .past_due ? "Past due" : rawValue.capitalized }
}
