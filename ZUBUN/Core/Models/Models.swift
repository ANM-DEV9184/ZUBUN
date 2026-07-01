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
}

/// `GET /api/staff/shift-stats` — exact keys from the `staff_shift_stats` RPC
/// (+ `overtime_until` appended by the route). Verified against the backend.
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
    let prevStampAt: String?
    let createdAt: String?
    let stampsCount: Int?

    /// Last 4 digits only for display (PDPL-friendly).
    var maskedPhone: String? {
        guard let phone, phone.count >= 4 else { return phone }
        return "•••• " + phone.suffix(4)
    }
}
