//
//  OwnerServiceSettings.swift
//  ZUBUN
//
//  Owner service methods for Settings + Payroll (Batches 3 & 4). All reachable
//  directly with the owner JWT (RPCs granted to `authenticated`, or RLS table
//  ops). Contracts verified against the source repo.
//

import Foundation

// MARK: - Settings

extension OwnerService {

    func programRule(venueID: String) async throws -> ProgramRule? {
        let rows: [ProgramRule] = try await supabase.restGet("program_rules",
            query: [
                .init(name: "select", value: "stamps_required,reward_text,daily_cap,expiry_days,grace_days"),
                .init(name: "venue_id", value: "eq.\(venueID)"),
                .init(name: "valid_until", value: "is.null"),
                .init(name: "order", value: "valid_from.desc"),
                .init(name: "limit", value: "1"),
            ], accessToken: session.ownerToken)
        return rows.first
    }

    func venueConfig(venueID: String) async throws -> VenueConfig? {
        let rows: [VenueConfig] = try await supabase.restGet("venues",
            query: [
                .init(name: "select", value: "loyalty_mode,points_rate,repeat_stamp_approval_minutes,staff_bonus_enabled,birthday_gift,birthday_gift_count,birthday_gift_label,branding"),
                .init(name: "id", value: "eq.\(venueID)"),
                .init(name: "limit", value: "1"),
            ], accessToken: session.ownerToken)
        return rows.first
    }

    func rewards(venueID: String) async throws -> [RewardItem] {
        try await supabase.restGet("program_rewards",
            query: [
                .init(name: "select", value: "id,label,points_cost,active,sort"),
                .init(name: "venue_id", value: "eq.\(venueID)"),
                .init(name: "order", value: "sort.asc"),
            ], accessToken: session.ownerToken)
    }

    func promotions(venueID: String) async throws -> [Promotion] {
        try await supabase.restGet("promotions",
            query: [
                .init(name: "select", value: "id,label,multiplier,starts_at,ends_at,active,recurrence,weekdays,daily_start,daily_end"),
                .init(name: "venue_id", value: "eq.\(venueID)"),
                .init(name: "order", value: "starts_at.desc"),
            ], accessToken: session.ownerToken)
    }

    @discardableResult
    func updateProgramRule(venueID: String, stampsRequired: Int, rewardText: String,
                           dailyCap: Int, expiryDays: Int, graceDays: Int) async throws -> String {
        struct P: Encodable {
            let pVenueId: String; let pStampsRequired: Int; let pRewardText: String
            let pDailyCap: Int; let pExpiryDays: Int; let pGraceDays: Int
        }
        return try await supabase.rpc("update_program_rule",
            params: P(pVenueId: venueID, pStampsRequired: stampsRequired, pRewardText: rewardText,
                      pDailyCap: dailyCap, pExpiryDays: expiryDays, pGraceDays: graceDays),
            accessToken: session.ownerToken)
    }

    @discardableResult
    func setRepeatApproval(venueID: String, minutes: Int) async throws -> DecideResult {
        struct P: Encodable { let pVenueId: String; let pMinutes: Int }
        return try await supabase.rpc("set_venue_repeat_approval", params: P(pVenueId: venueID, pMinutes: minutes), accessToken: session.ownerToken)
    }

    @discardableResult
    func setStaffBonus(venueID: String, enabled: Bool) async throws -> DecideResult {
        struct P: Encodable { let pVenueId: String; let pEnabled: Bool }
        return try await supabase.rpc("set_venue_staff_bonus", params: P(pVenueId: venueID, pEnabled: enabled), accessToken: session.ownerToken)
    }

    @discardableResult
    func setBirthdayGift(venueID: String, gift: String, count: Int, label: String?) async throws -> DecideResult {
        let params: [String: JSONParam] = [
            "p_venue_id": .string(venueID), "p_gift": .string(gift),
            "p_count": .int(count), "p_label": .optString(label),
        ]
        return try await supabase.rpc("set_venue_birthday_gift", params: params, accessToken: session.ownerToken)
    }

    @discardableResult
    func setBranding(venueID: String, branding: BrandingBlob) async throws -> DecideResult {
        struct P: Encodable { let pVenueId: String; let pBranding: BrandingBlob }
        return try await supabase.rpc("set_branding", params: P(pVenueId: venueID, pBranding: branding), accessToken: session.ownerToken)
    }

    func addReward(venueID: String, label: String, pointsCost: Int?) async throws {
        struct Row: Encodable { let venueId: String; let label: String; let pointsCost: Int?; let sort: Int }
        try await supabase.restInsert("program_rewards",
            body: Row(venueId: venueID, label: label, pointsCost: pointsCost, sort: 0),
            accessToken: session.ownerToken)
    }

    func setRewardActive(id: String, active: Bool) async throws {
        struct Body: Encodable { let active: Bool }
        try await supabase.restPatch("program_rewards", query: [.init(name: "id", value: "eq.\(id)")],
                                     body: Body(active: active), accessToken: session.ownerToken)
    }

    func deleteReward(id: String) async throws {
        try await supabase.restDelete("program_rewards", query: [.init(name: "id", value: "eq.\(id)")], accessToken: session.ownerToken)
    }

    func addPromotion(venueID: String, label: String, multiplier: Int, recurrence: String,
                      startsAt: String, endsAt: String, weekdays: [Int]) async throws {
        struct Row: Encodable {
            let venueId: String; let label: String; let multiplier: Int; let recurrence: String
            let startsAt: String; let endsAt: String; let weekdays: [Int]
        }
        try await supabase.restInsert("promotions",
            body: Row(venueId: venueID, label: label, multiplier: multiplier, recurrence: recurrence,
                      startsAt: startsAt, endsAt: endsAt, weekdays: weekdays),
            accessToken: session.ownerToken)
    }

    func deletePromotion(id: String) async throws {
        try await supabase.restDelete("promotions", query: [.init(name: "id", value: "eq.\(id)")], accessToken: session.ownerToken)
    }

    // Venue lifecycle

    @discardableResult
    func createVenue(name: String, vertical: String, stampsRequired: Int, rewardText: String, dailyCap: Int) async throws -> CreateVenueResult {
        struct P: Encodable {
            let pVenueName: String; let pVertical: String; let pStampsRequired: Int
            let pRewardText: String; let pDailyCap: Int
        }
        return try await supabase.rpc("owner_create_venue",
            params: P(pVenueName: name, pVertical: vertical, pStampsRequired: stampsRequired, pRewardText: rewardText, pDailyCap: dailyCap),
            accessToken: session.ownerToken)
    }

    @discardableResult
    func pauseVenue(venueID: String) async throws -> DecideResult {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_pause_venue", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }

    @discardableResult
    func activateVenue(venueID: String) async throws -> DecideResult {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_activate_venue", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }
}

// MARK: - Payroll

extension OwnerService {

    func payConfigs(venueID: String) async throws -> [PayConfig] {
        try await supabase.restGet("staff_pay_config",
            query: [
                .init(name: "select", value: "staff_id,pay_type,base_rate,overtime_multiplier,currency,payday_dom,deduct_absences,premium_multiplier"),
                .init(name: "venue_id", value: "eq.\(venueID)"),
            ], accessToken: session.ownerToken)
    }

    func payslips(venueID: String) async throws -> [Payslip] {
        try await supabase.restGet("staff_payslips",
            query: [
                .init(name: "select", value: "id,staff_id,period_month,regular_minutes,overtime_minutes,premium_minutes,premium_amount,deduction_amount,gross_amount,adjustment_total,currency,status,expected_pay_date,paid_at,on_time"),
                .init(name: "venue_id", value: "eq.\(venueID)"),
                .init(name: "order", value: "period_month.desc"),
                .init(name: "limit", value: "200"),
            ], accessToken: session.ownerToken)
    }

    func adjustments(payslipIDs: [String]) async throws -> [PayslipAdjustment] {
        guard !payslipIDs.isEmpty else { return [] }
        let inList = "(" + payslipIDs.joined(separator: ",") + ")"
        return try await supabase.restGet("staff_payslip_adjustments",
            query: [
                .init(name: "select", value: "id,payslip_id,label,amount,note"),
                .init(name: "payslip_id", value: "in.\(inList)"),
            ], accessToken: session.ownerToken)
    }

    func upsertPayConfig(venueID: String, staffID: String, payType: String, baseRate: Double,
                         overtimeMultiplier: Double, paydayDom: Int, premiumMultiplier: Double,
                         deductAbsences: Bool) async throws {
        struct Row: Encodable {
            let staffId: String; let venueId: String; let payType: String; let baseRate: Double
            let overtimeMultiplier: Double; let currency: String; let paydayDom: Int
            let deductAbsences: Bool; let premiumMultiplier: Double
        }
        try await supabase.restInsert("staff_pay_config",
            body: Row(staffId: staffID, venueId: venueID, payType: payType, baseRate: baseRate,
                      overtimeMultiplier: overtimeMultiplier, currency: "AED", paydayDom: paydayDom,
                      deductAbsences: deductAbsences, premiumMultiplier: premiumMultiplier),
            upsertOnConflict: "staff_id", accessToken: session.ownerToken)
    }

    @discardableResult
    func generatePayslips(venueID: String, month: String) async throws -> DecideResult {
        struct P: Encodable { let pVenueId: String; let pMonth: String }
        return try await supabase.rpc("generate_payslips", params: P(pVenueId: venueID, pMonth: "\(month)-01"), accessToken: session.ownerToken)
    }

    @discardableResult
    func addAdjustment(payslipID: String, label: String, amount: Double, note: String?) async throws -> DecideResult {
        let params: [String: JSONParam] = [
            "p_payslip_id": .string(payslipID), "p_label": .string(label),
            "p_amount": .double(amount), "p_note": .optString(note),
        ]
        return try await supabase.rpc("add_payslip_adjustment", params: params, accessToken: session.ownerToken)
    }

    @discardableResult
    func removeAdjustment(id: String) async throws -> DecideResult {
        struct P: Encodable { let pId: String }
        return try await supabase.rpc("remove_payslip_adjustment", params: P(pId: id), accessToken: session.ownerToken)
    }

    @discardableResult
    func markPayslipPaid(id: String) async throws -> DecideResult {
        let iso = ISO8601DateFormatter().string(from: Date())
        let params: [String: JSONParam] = ["p_payslip_id": .string(id), "p_paid_at": .string(iso)]
        return try await supabase.rpc("mark_payslip_paid", params: params, accessToken: session.ownerToken)
    }
}
