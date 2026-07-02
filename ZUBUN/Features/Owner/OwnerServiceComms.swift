//
//  OwnerServiceComms.swift
//  ZUBUN
//
//  Owner service methods for Campaigns + Support (Batch 5). Campaign list/create
//  are RLS table ops; send is the `enqueue_campaign` RPC. Support is RLS table
//  ops on support_tickets/support_messages (the Next.js routes are cookie-only,
//  so the app talks to PostgREST directly with the owner JWT).
//

import Foundation

// MARK: - Campaigns

extension OwnerService {

    func feedbackSummary(venueID: String) async throws -> FeedbackSummary {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_feedback_summary", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }

    /// Per-staff performance (issuance + attendance) over a Dubai date range.
    func staffPerformance(venueID: String, from: String, to: String) async throws -> [StaffPerformance] {
        struct P: Encodable { let pVenueId: String; let pFrom: String; let pTo: String }
        return try await supabase.rpc("owner_staff_performance",
                                      params: P(pVenueId: venueID, pFrom: from, pTo: to),
                                      accessToken: session.ownerToken)
    }

    func merchantPlan() async throws -> MerchantPlan? {
        guard let mid = merchantID else { return nil }
        let rows: [MerchantPlan] = try await supabase.restGet("merchants",
            query: [
                .init(name: "select", value: "plan_tier,billing_status,marketing_msgs_used"),
                .init(name: "id", value: "eq.\(mid)"),
                .init(name: "limit", value: "1"),
            ], accessToken: session.ownerToken)
        return rows.first
    }

    func campaigns(venueID: String) async throws -> [CampaignRow] {
        try await supabase.restGet("campaigns",
            query: [
                .init(name: "select", value: "id,name,status,segment_def,scheduled_at,created_at"),
                .init(name: "venue_id", value: "eq.\(venueID)"),
                .init(name: "order", value: "created_at.desc"),
                .init(name: "limit", value: "50"),
            ], accessToken: session.ownerToken)
    }

    /// Approved marketing templates available to this merchant (+ platform).
    func marketingTemplates() async throws -> [TemplateRow] {
        let mid = merchantID ?? "00000000-0000-0000-0000-000000000000"
        let rows: [TemplateRow] = try await supabase.restGet("templates",
            query: [
                .init(name: "select", value: "id,name,language,status"),
                .init(name: "category", value: "eq.marketing"),
                .init(name: "or", value: "(merchant_id.is.null,merchant_id.eq.\(mid))"),
            ], accessToken: session.ownerToken)
        return rows.filter { $0.isApproved }
    }

    func createCampaign(venueID: String, name: String, templateID: String,
                        segment: String, daysInactive: Int) async throws {
        struct Row: Encodable {
            let venueId: String; let name: String; let templateId: String
            let segmentDef: CampaignSegmentDef; let status: String
        }
        let seg = segment == "lapsed"
            ? CampaignSegmentDef(all: nil, daysInactive: daysInactive)
            : CampaignSegmentDef(all: true, daysInactive: nil)
        try await supabase.restInsert("campaigns",
            body: Row(venueId: venueID, name: name, templateId: templateID, segmentDef: seg, status: "draft"),
            accessToken: session.ownerToken)
    }

    @discardableResult
    func sendCampaign(id: String) async throws -> EnqueueResult {
        struct P: Encodable { let pCampaignId: String }
        return try await supabase.rpc("enqueue_campaign", params: P(pCampaignId: id), accessToken: session.ownerToken)
    }
}

// MARK: - Support

extension OwnerService {

    func supportTickets() async throws -> [SupportTicket] {
        try await supabase.restGet("support_tickets",
            query: [
                .init(name: "select", value: "id,subject,status,last_message_at,last_message_preview,owner_last_read_at,created_at"),
                .init(name: "order", value: "last_message_at.desc.nullslast"),
                .init(name: "limit", value: "100"),
            ], accessToken: session.ownerToken)
    }

    func supportMessages(ticketID: String) async throws -> [SupportMessage] {
        try await supabase.restGet("support_messages",
            query: [
                .init(name: "select", value: "id,sender_role,body,created_at"),
                .init(name: "ticket_id", value: "eq.\(ticketID)"),
                .init(name: "sender_role", value: "neq.note"),   // hide internal admin notes
                .init(name: "order", value: "created_at.asc"),
            ], accessToken: session.ownerToken)
        }

    /// Creates a ticket + first owner message (client-generated id so we don't
    /// need a representation round-trip).
    func createTicket(subject: String, category: String, body: String) async throws {
        guard let mid = merchantID else { throw APIError.notConfigured("No merchant_id.") }
        let ticketID = UUID().uuidString.lowercased()
        let nowISO = ISO8601DateFormatter().string(from: Date())
        struct Ticket: Encodable {
            let id: String; let merchantId: String; let subject: String; let category: String
            let status: String; let lastMessagePreview: String; let lastMessageAt: String; let ownerLastReadAt: String
        }
        try await supabase.restInsert("support_tickets",
            body: Ticket(id: ticketID, merchantId: mid, subject: subject, category: category, status: "open",
                         lastMessagePreview: String(body.prefix(140)), lastMessageAt: nowISO, ownerLastReadAt: nowISO),
            accessToken: session.ownerToken)
        try await insertMessage(ticketID: ticketID, body: body, preview: false)
    }

    func replyToTicket(ticketID: String, body: String) async throws {
        try await insertMessage(ticketID: ticketID, body: body, preview: true)
    }

    private func insertMessage(ticketID: String, body: String, preview: Bool) async throws {
        struct Msg: Encodable { let ticketId: String; let senderRole: String; let body: String }
        try await supabase.restInsert("support_messages",
            body: Msg(ticketId: ticketID, senderRole: "owner", body: body),
            accessToken: session.ownerToken)
        if preview {
            struct Patch: Encodable { let lastMessagePreview: String; let lastMessageAt: String; let ownerLastReadAt: String }
            let nowISO = ISO8601DateFormatter().string(from: Date())
            try await supabase.restPatch("support_tickets", query: [.init(name: "id", value: "eq.\(ticketID)")],
                body: Patch(lastMessagePreview: String(body.prefix(140)), lastMessageAt: nowISO, ownerLastReadAt: nowISO),
                accessToken: session.ownerToken)
        }
    }

    func markTicketRead(ticketID: String) async throws {
        struct Patch: Encodable { let ownerLastReadAt: String }
        try await supabase.restPatch("support_tickets", query: [.init(name: "id", value: "eq.\(ticketID)")],
            body: Patch(ownerLastReadAt: ISO8601DateFormatter().string(from: Date())), accessToken: session.ownerToken)
    }

    func rateTicket(ticketID: String, rating: Int, comment: String?) async throws {
        struct Patch: Encodable { let csatRating: Int; let csatComment: String? }
        try await supabase.restPatch("support_tickets", query: [.init(name: "id", value: "eq.\(ticketID)")],
            body: Patch(csatRating: rating, csatComment: comment), accessToken: session.ownerToken)
    }
}
