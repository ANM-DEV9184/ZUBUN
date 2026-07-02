//
//  SupportModels.swift
//  ZUBUN
//
//  Shared support/ticketing models for the native apps (all roles). Backed by
//  /api/app/support + /api/app/support/thread (see dayem migration 20260703000160).
//  Named `AppTicket*` to avoid clashing with the owner's legacy Support* models.
//

import Foundation

struct AppTicket: Decodable, Identifiable, Hashable {
    let id: String
    let subject: String?
    let status: String?
    let category: String?
    let lastMessagePreview: String?
    let lastMessageAt: String?
    let unread: Bool?

    /// Owner-facing plain-language status.
    var statusLabel: String {
        switch status {
        case "open":     return String(localized: "ticket.status.open", defaultValue: "Open")
        case "pending":  return String(localized: "ticket.status.pending", defaultValue: "In progress")
        case "resolved": return String(localized: "ticket.status.resolved", defaultValue: "Resolved")
        case "closed":   return String(localized: "ticket.status.closed", defaultValue: "Closed")
        default:         return (status ?? "").capitalized
        }
    }
    var isClosed: Bool { status == "closed" || status == "resolved" }
}

struct AppTicketsResponse: Decodable {
    let tickets: [AppTicket]
    let unreadCount: Int?
}

struct AppTicketMessage: Decodable, Identifiable, Hashable {
    let id: String
    let senderRole: String?
    let body: String?
    let imageUrl: String?
    let createdAt: String?

    /// A message is "mine" (right-aligned) unless it's from support/system.
    var isMine: Bool { !(senderRole == "admin" || senderRole == "system") }
    var isSystem: Bool { senderRole == "system" }
}

struct AppTicketMeta: Decodable, Hashable {
    let id: String
    let subject: String?
    let status: String?
    let category: String?
    let csatRating: Int?
    var isResolvedOrClosed: Bool { status == "resolved" || status == "closed" }
}

struct AppThreadResponse: Decodable {
    let ticket: AppTicketMeta
    let messages: [AppTicketMessage]
}

struct CreateTicketResponse: Decodable {
    let ticketId: String?
}

/// Ticket categories offered when composing (mirror the server whitelist).
enum TicketCategory: String, CaseIterable, Identifiable {
    case billing, technical, how_to, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .billing:   return String(localized: "ticket.cat.billing", defaultValue: "Billing")
        case .technical: return String(localized: "ticket.cat.technical", defaultValue: "Technical issue")
        case .how_to:    return String(localized: "ticket.cat.howto", defaultValue: "How do I…")
        case .other:     return String(localized: "ticket.cat.other", defaultValue: "Something else")
        }
    }
}
