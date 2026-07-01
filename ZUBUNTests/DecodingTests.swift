//
//  DecodingTests.swift
//  ZUBUNTests
//
//  Verifies the Codable DTOs decode the EXACT snake_case JSON the backend returns
//  (contracts verified against the source repo). Guards against field-name drift
//  like the staff_shift_stats bug.
//

import Testing
import Foundation
@testable import ZUBUN

@MainActor
struct DecodingTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder.zubun.decode(T.self, from: Data(json.utf8))
    }

    @Test func customerCard() throws {
        let json = """
        { "membership_id": "m1", "venue_id": "v1", "venue_name": "Al Reem Café",
          "logo_url": null, "loyalty_mode": "stamps", "venue_paused": false,
          "stamps_count": 3, "stamps_required": 8, "points_balance": 0,
          "tier": "silver", "reward_text": "Free coffee", "reward_ready": false,
          "identity_qr": "dayem:c:abc", "card_link": "https://zubun.io/card/x" }
        """
        let card = try decode(CustomerCard.self, json)
        #expect(card.venueName == "Al Reem Café")
        #expect(card.loyaltyMode == .stamps)
        #expect(card.tier == .silver)
        #expect(card.stampsRequired == 8)
        #expect(abs(card.progress - 3.0 / 8.0) < 0.0001)
    }

    @Test func customerCardPointsModeNullRequired() throws {
        // stamps_required is null in points mode — must not fail decoding.
        let json = """
        { "membership_id": "m2", "venue_id": "v1", "venue_name": "V", "logo_url": null,
          "loyalty_mode": "points", "venue_paused": false, "stamps_count": 0,
          "stamps_required": null, "points_balance": 120, "tier": "gold",
          "reward_text": null, "reward_ready": true, "identity_qr": "dayem:c:z", "card_link": null }
        """
        let card = try decode(CustomerCard.self, json)
        #expect(card.stampsRequired == nil)
        #expect(card.progress == 0)
        #expect(card.pointsBalance == 120)
    }

    @Test func shiftStats() throws {
        let json = """
        { "today": 4, "venue_today": 20, "my_7d": 31,
          "leaderboard": [ { "name": "Ayesha", "today": 12 }, { "name": "Omar", "today": 8 } ],
          "overtime_until": null }
        """
        let s = try decode(ShiftStats.self, json)
        #expect(s.today == 4)
        #expect(s.venueToday == 20)
        #expect(s.my7d == 31)
        #expect(s.leaderboard?.count == 2)
        #expect(s.rank(forName: "Omar") == 2)
    }

    @Test func stampResult() throws {
        let json = #"{ "result": "reward_issued", "stamps_count": 0, "stamps_required": 8, "reward_text": "Free coffee" }"#
        let r = try decode(StampResult.self, json)
        #expect(r.result == .rewardIssued)
        #expect(r.stampsRequired == 8)
        #expect(r.rewardText == "Free coffee")
    }

    @Test func memberRow() throws {
        let json = """
        { "id": "m1", "card_state": "active", "stamps_count": 5, "tier": "gold",
          "marketing_opt_in": true, "last_visit_at": "2026-06-30T10:00:00Z", "created_at": "2026-01-01T00:00:00Z",
          "customers": { "phone_e164": "+971501234567", "name_optional": "Sara" } }
        """
        let m = try decode(MemberRow.self, json)
        #expect(m.displayName == "Sara")
        #expect(m.maskedPhone == "•••• 4567")
        #expect(m.tier == .gold)
    }

    @Test func payslipNet() throws {
        let json = """
        { "id": "p1", "staff_id": "s1", "period_month": "2026-06-01", "regular_minutes": 9600,
          "overtime_minutes": 120, "premium_minutes": 0, "premium_amount": 0, "deduction_amount": 0,
          "gross_amount": 4500, "adjustment_total": -50, "currency": "AED", "status": "finalized",
          "expected_pay_date": "2026-07-01", "paid_at": null, "on_time": null }
        """
        let p = try decode(Payslip.self, json)
        #expect(p.grossAmount == 4500)
        #expect(p.adjustmentTotal == -50)
        #expect(p.net == 4450)
    }

    @Test func campaignAndSegment() throws {
        let json = #"{ "id": "c1", "name": "Weekend", "status": "draft", "segment_def": { "all": true }, "scheduled_at": null, "created_at": "2026-06-30T00:00:00Z" }"#
        let c = try decode(CampaignRow.self, json)
        #expect(c.segmentDef?.all == true)
        #expect(c.audienceLabel == "All members")

        let lapsed = #"{ "id": "c2", "name": "Winback", "status": "sent", "segment_def": { "days_inactive": 30 }, "scheduled_at": null, "created_at": null }"#
        let c2 = try decode(CampaignRow.self, lapsed)
        #expect(c2.audienceLabel == "Lapsed 30d+")
    }

    @Test func supportTicketUnread() throws {
        let unreadJSON = """
        { "id": "t1", "subject": "Help", "status": "open",
          "last_message_at": "2026-06-30T12:00:00Z", "last_message_preview": "hi",
          "owner_last_read_at": "2026-06-30T11:00:00Z", "created_at": "2026-06-30T10:00:00Z" }
        """
        #expect(try decode(SupportTicket.self, unreadJSON).unread == true)

        let readJSON = """
        { "id": "t2", "subject": "Help", "status": "resolved",
          "last_message_at": "2026-06-30T12:00:00Z", "last_message_preview": "hi",
          "owner_last_read_at": "2026-06-30T13:00:00Z", "created_at": "2026-06-30T10:00:00Z" }
        """
        let read = try decode(SupportTicket.self, readJSON)
        #expect(read.unread == false)
        #expect(read.isClosed == true)
    }

    @Test func attendanceRow() throws {
        let json = """
        { "kind": "entry", "entry_id": "e1", "staff_id": "s1", "name": "Omar", "work_date": "2026-06-30",
          "clock_in_at": "2026-06-30T05:00:00Z", "clock_out_at": "2026-06-30T13:00:00Z",
          "worked_minutes": 480, "paid_worked_minutes": 450, "break_minutes": 30,
          "overtime_minutes": 0, "overtime_status": "none", "early_leave_minutes": 0, "late_minutes": 5,
          "status": "closed", "source": "clock", "shift_start": "09:00", "shift_end": "17:00" }
        """
        let r = try decode(AttendanceRow.self, json)
        #expect(r.name == "Omar")
        #expect(r.paidWorkedMinutes == 450)
        #expect(r.isOpen == false)
        #expect(r.isNoShow == false)
    }
}
