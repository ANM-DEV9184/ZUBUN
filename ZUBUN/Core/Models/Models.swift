//
//  Models.swift
//  ZUBUN
//
//  Codable DTOs for the REST + RPC contracts (spec §8, §9.3). Keys decode from
//  snake_case automatically (see JSONCoders). ISO date strings are kept raw and
//  parsed on demand.
//

import Foundation

// MARK: - Generic envelopes

/// Most loyalty/clock/redeem endpoints return at least `{ result: "<code>" }`.
struct ResultEnvelope: Decodable {
    let result: ResultCode
    let message: String?
}

enum LoyaltyMode: String, Codable, Sendable {
    case stamps, points
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LoyaltyMode(rawValue: raw) ?? .stamps
    }
}

enum MemberTier: String, Codable, Sendable {
    case bronze, silver, gold
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MemberTier(rawValue: raw.lowercased()) ?? .bronze
    }
    var label: String { rawValue.capitalized }
}

// MARK: - Staff auth

struct StaffAuthResponse: Decodable {
    let ok: Bool
    let staffId: String
    let displayName: String
    let venueId: String
    let token: String
    let expiresAt: String?
}

// MARK: - Loyalty results

/// Result of a stamp / bonus / fallback. Optional fields populate on success.
struct StampResult: Decodable {
    let result: ResultCode
    let stampsCount: Int?
    let stampsRequired: Int?
    let pointsBalance: Int?
    let rewardText: String?
    let customerName: String?
    let tier: MemberTier?
}

struct RedeemResult: Decodable {
    let result: ResultCode
    let rewardLabel: String?
}

// MARK: - Clock / attendance

struct ClockResult: Decodable {
    let result: ResultCode
    let workedMinutes: Int?
    let paidMinutes: Int?
    let overtimeMinutes: Int?
    let lateMinutes: Int?
    let earlyLeaveMinutes: Int?
}

/// One row of the staffer's own schedule (GET /api/staff/shifts).
struct StaffShift: Decodable, Identifiable {
    let id: String
    let workDate: String        // "2026-07-02"
    let startTime: String?      // "08:00:00" — nil on an off day
    let endTime: String?
    let isOff: Bool
    let leaveType: String?
    let unpaidBreakMinutes: Int?

    /// "08:00–16:00", or the leave/off label.
    var displayTimes: String {
        if isOff { return (leaveType.map { $0.capitalized } ?? "Day off") }
        guard let s = startTime, let e = endTime else { return "—" }
        return "\(String(s.prefix(5)))–\(String(e.prefix(5)))"
    }

    /// "Thu 2 Jul" for the row label.
    var dateLabel: String {
        let inF = DateFormatter(); inF.calendar = Calendar(identifier: .gregorian)
        inF.dateFormat = "yyyy-MM-dd"; inF.timeZone = TimeZone(identifier: "Asia/Dubai")
        guard let d = inF.date(from: workDate) else { return workDate }
        let out = DateFormatter(); out.dateFormat = "EEE d MMM"
        out.timeZone = TimeZone(identifier: "Asia/Dubai")
        return out.string(from: d)
    }
}

struct StaffShiftsResponse: Decodable { let shifts: [StaffShift] }

// MARK: - Staff self-service (Phase 6): attendance / achievements / pay / colleagues

struct StaffAttendanceEntry: Decodable, Identifiable {
    let entryId: String?
    let kind: String?
    let workDate: String?
    let clockInAt: String?
    let clockOutAt: String?
    let workedMinutes: Int?
    let paidWorkedMinutes: Int?
    let breakMinutes: Int?
    let overtimeMinutes: Int?
    let overtimeStatus: String?
    let earlyLeaveMinutes: Int?
    let lateMinutes: Int?
    let status: String?
    var id: String { entryId ?? "\(workDate ?? "")-\(clockInAt ?? "")" }
    var isNoShow: Bool { kind == "no_show" || status == "no_show" }
}

struct StaffAttendanceResponse: Decodable {
    let otPayPolicy: String?
    let entries: [StaffAttendanceEntry]
}

struct StaffAchievements: Decodable {
    let lifetime: Int?
    let month: Int?
    let rank: Int?
    let bestDay: Int?
    let streak: Int?
    let nextMilestone: Int?
}

struct StaffPayslip: Decodable, Identifiable {
    let id: String
    let periodMonth: String?
    let grossAmount: Double?
    let adjustmentTotal: Double?
    let currency: String?
    let status: String?
    let regularMinutes: Int?
    let overtimeMinutes: Int?
    let paidAt: String?
    let confirmedAt: String?
    var isPaid: Bool { status == "paid" }
}

struct PayAdjustment: Decodable, Identifiable {
    let id: String
    let payslipId: String?
    let label: String?
    let amount: Double?
    let note: String?
}

struct StaffPayslipsResponse: Decodable {
    let payslips: [StaffPayslip]
    let adjustments: [PayAdjustment]
}

struct StaffColleague: Decodable, Identifiable {
    let id: String
    let displayName: String?
    var name: String { displayName ?? "Colleague" }
}

struct StaffColleaguesResponse: Decodable { let colleagues: [StaffColleague] }

// MARK: - Owner feedback / NPS (owner_feedback_summary)

struct FeedbackComment: Decodable, Identifiable {
    let score: Int?
    let comment: String?
    let at: String?
    var id: String { (at ?? "") + "-" + (comment ?? "") }
}

struct FeedbackSummary: Decodable {
    let count: Int?
    let avg: Double?
    let promoters: Int?
    let detractors: Int?
    let dist: [String: Int]?
    let recentLow: [FeedbackComment]?
}

/// One row of owner_staff_performance (issuance + attendance over a date range).
struct StaffPerformance: Decodable, Identifiable {
    let staffId: String
    let name: String?
    let status: String?
    let stamps: Int?
    let manual: Int?
    let manualShare: Int?
    let workedMinutes: Int?
    let overtimeMinutes: Int?
    let lateMinutes: Int?
    let noShows: Int?
    let daysWorked: Int?
    var id: String { staffId }
    var displayName: String { name ?? "Staff" }
}

/// `GET /api/staff/shift-stats` — exact keys from the `staff_shift_stats` RPC
/// (+ `overtime_until` appended by the route). Verified against the backend.
///
/// Decoded by normalizing keys (strip non-alphanumerics, lowercase) so it's
/// immune to `convertFromSnakeCase`'s quirky handling of digit-adjacent keys
/// like `my_7d`.
struct ShiftStats: Decodable {
    let today: Int?           // my stamps since Dubai midnight
    let venueToday: Int?      // all-staff stamps at the venue today
    let my7d: Int?            // my stamps in the last 7 days
    let leaderboard: [LeaderRow]?
    let overtimeUntil: String?

    struct LeaderRow: Decodable, Hashable {
        let name: String?
        let today: Int?
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        var ints: [String: Int] = [:]
        var strings: [String: String] = [:]
        var board: [LeaderRow]?
        for key in container.allKeys {
            let n = norm(key.stringValue)
            if n == "leaderboard" {
                board = try? container.decode([LeaderRow].self, forKey: key)
            } else if let i = try? container.decode(Int.self, forKey: key) {
                ints[n] = i
            } else if let s = try? container.decode(String.self, forKey: key) {
                strings[n] = s
            }
        }
        today = ints["today"]
        venueToday = ints["venuetoday"]
        my7d = ints["my7d"]
        leaderboard = board
        overtimeUntil = strings["overtimeuntil"]
    }

    /// My 1-based rank on today's leaderboard, if present.
    func rank(forName name: String?) -> Int? {
        guard let name, let board = leaderboard else { return nil }
        return board.firstIndex { $0.name == name }.map { $0 + 1 }
    }
}

// MARK: - Customer wallet (spec §9.3)

struct CustomerCard: Decodable, Identifiable {
    let membershipId: String
    let venueId: String
    let venueName: String
    let logoUrl: String?
    let loyaltyMode: LoyaltyMode
    let venuePaused: Bool
    let stampsCount: Int
    let stampsRequired: Int?     // null in points mode
    let pointsBalance: Int
    let tier: MemberTier
    let rewardText: String?
    let rewardReady: Bool
    let identityQr: String
    let cardLink: String?

    var id: String { membershipId }

    var progress: Double {
        guard let required = stampsRequired, required > 0 else { return 0 }
        return min(1, Double(stampsCount) / Double(required))
    }
}

struct CustomerCardsResponse: Decodable {
    let cards: [CustomerCard]
}

struct RewardMenuItem: Decodable, Identifiable {
    let id: String
    let label: String
    let pointsCost: Int
}

struct ActiveReward: Decodable {
    let rewardText: String?
    let expiresAt: String?
    let rewardQr: String
}

struct CustomerCardDetail: Decodable {
    let membershipId: String
    let venueId: String
    let venueName: String
    let loyaltyMode: LoyaltyMode
    let stampsCount: Int
    let stampsRequired: Int?     // null in points mode
    let pointsBalance: Int
    let tier: MemberTier
    let rewardText: String?
    let identityQr: String
    let reward: ActiveReward?
    let rewardsMenu: [RewardMenuItem]?
    let history: [String]?
}

struct JoinResult: Decodable {
    let result: ResultCode
    let cardUrl: String?
    let cardLink: String?
}

struct FeedbackResult: Decodable {
    let result: ResultCode?
    let reviewUrl: String?
}

// MARK: - Owner dashboard (lighter; RPC-backed)

/// Matches `owner_consolidated_kpis(p_merchant_id)` JSONB (merchant-wide).
struct OwnerKPIs: Decodable {
    let venues: Int?
    let members: Int?
    let activeCards: Int?
    let stampsToday: Int?
    let stamps7d: Int?
    let stamps30d: Int?
    let perVenue: [PerVenueKPI]?
}

struct PerVenueKPI: Decodable, Identifiable {
    let venueId: String
    let name: String
    let members: Int?
    let activeCards: Int?
    let stamps7d: Int?
    var id: String { venueId }
}

/// Matches an element of `owner_stamp_approvals(p_venue_id)` JSONB array.
struct StampApproval: Decodable, Identifiable {
    let id: String
    let customerName: String?
    let phone: String?
    let staffName: String?
    let reason: String?
    let prevStampAt: String?
    let createdAt: String?
    let stampsCount: Int?

    /// Why approval is needed — for the owner's context.
    var reasonLabel: String {
        reason == "daily_cap"
            ? String(localized: "approval.reason.cap", defaultValue: "Over daily limit")
            : String(localized: "approval.reason.repeat", defaultValue: "Rapid repeat")
    }

    /// Last 4 digits only for display (PDPL-friendly).
    var maskedPhone: String? {
        guard let phone, phone.count >= 4 else { return phone }
        return "•••• " + phone.suffix(4)
    }
}

// MARK: - Notification inbox (GET /api/customer/notifications)

/// One in-app notification (venue-scoped campaign push, mirrored to the inbox).
struct CustomerNotification: Decodable, Identifiable {
    let id: String
    let venueId: String?
    let membershipId: String?
    let campaignId: String?
    let category: String
    let title: String
    let body: String
    let deepLink: String?
    let readAt: String?        // ISO8601; nil = unread
    let createdAt: String      // ISO8601

    var isUnread: Bool { readAt == nil }
}

struct NotificationsResponse: Decodable {
    let notifications: [CustomerNotification]
    let unread: Int
}

/// Result of the DEBUG push self-test (POST /api/customer/notifications/test).
struct TestPushResult: Decodable {
    let devices: Int
    let delivered: Int
    let results: [Device]

    struct Device: Decodable {
        let status: Int
        let ok: Bool
        let reason: String?
    }

    /// One-line summary for the debug banner.
    var summary: String {
        if devices == 0 { return "No device registered — enable notifications, then relaunch." }
        let reasons = results.compactMap { $0.reason }.joined(separator: ", ")
        let base = "\(delivered)/\(devices) delivered"
        return reasons.isEmpty ? base : "\(base) · \(reasons)"
    }
}
