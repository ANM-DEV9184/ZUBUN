//
//  OwnerModels.swift
//  ZUBUN
//
//  DTOs for the Owner dashboard depth (Batch 1: venues, members, approval
//  queues). Field names match the verified backend contracts (PostgREST selects
//  + owner_* RPCs).
//

import Foundation

// MARK: - Venue switcher

struct OwnerVenue: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String   // "active" | "paused"

    var isPaused: Bool { status == "paused" }
}

// MARK: - Members

struct MemberCustomer: Decodable, Hashable {
    let phoneE164: String?
    let nameOptional: String?
}

struct MemberRow: Decodable, Identifiable, Hashable {
    let id: String
    let cardState: String?
    let stampsCount: Int?
    let tier: MemberTier?
    let marketingOptIn: Bool?
    let lastVisitAt: String?
    let createdAt: String?
    let customers: MemberCustomer?

    var displayName: String {
        customers?.nameOptional ?? customers?.phoneE164 ?? "Member"
    }
    var maskedPhone: String? {
        guard let p = customers?.phoneE164, p.count >= 4 else { return customers?.phoneE164 }
        return "•••• " + p.suffix(4)
    }
}

/// One stamp row in the member detail (with the staff who issued it).
struct MemberStamp: Decodable, Identifiable, Hashable {
    let id: String
    let createdAt: String?
    let fallbackFlag: Bool?
    let staffUsers: StaffRef?
    struct StaffRef: Decodable, Hashable { let displayName: String? }
}

/// One redemption token row in the member detail.
struct MemberReward: Decodable, Identifiable, Hashable {
    let id: String
    let status: String?
    let createdAt: String?
    let consumedAt: String?
    let expiresAt: String?
    let voidReason: String?
}

// MARK: - Approval queues

struct LeaveRequestRow: Decodable, Identifiable, Hashable {
    let id: String
    let staffId: String?
    let staffName: String?
    let fromDate: String?
    let toDate: String?
    let leaveType: String?
    let reason: String?
    let createdAt: String?
}

struct DayoffRequestRow: Decodable, Identifiable, Hashable {
    let id: String
    let staffId: String?
    let staffName: String?
    let fromDate: String?
    let toDate: String?
    let reason: String?
    let createdAt: String?
}

struct ShiftSwapRow: Decodable, Identifiable, Hashable {
    let id: String
    let fromName: String?
    let toName: String?
    let workDate: String?
    let startTime: String?
    let endTime: String?
    let reason: String?
}

// MARK: - Rota & attendance

struct OwnerStaff: Decodable, Identifiable, Hashable {
    let id: String
    let displayName: String?
    let status: String?
    let onboarded: Bool?
    var isActive: Bool { status == "active" }
    var name: String { displayName ?? "Staff" }
    /// Pending = created but hasn't set a PIN via their invite yet.
    var isPending: Bool { onboarded == false }
}

/// Result of POST /api/owner/staff-add — the onboarding invite to share.
struct StaffInvite: Decodable {
    let id: String?
    let inviteUrl: String?
}

// MARK: - Managers (RBAC v1)

struct Manager: Decodable, Identifiable {
    let id: String
    let authUserId: String
    let email: String
    let createdAt: String?
}

struct ManagersResponse: Decodable { let managers: [Manager] }

// MARK: - Analytics (venue_kpis / venue_daily_stats)

struct VenueKPIs: Decodable {
    let members: Int?
    let activeCards: Int?
    let stampsToday: Int?
    let stamps7d: Int?
    let stamps30d: Int?
    let stampsPrev30d: Int?
    let rewardsIssued30d: Int?
    let rewardsRedeemed30d: Int?
    let newMembers7d: Int?
    let newMembersPrev7d: Int?

    /// Percent change vs the previous window (nil when the base is 0).
    static func delta(_ current: Int?, _ previous: Int?) -> Int? {
        guard let p = previous, p > 0, let c = current else { return nil }
        return Int((Double(c - p) / Double(p) * 100).rounded())
    }
    var stampsDelta: Int? { Self.delta(stamps30d, stampsPrev30d) }
    var newMembersDelta: Int? { Self.delta(newMembers7d, newMembersPrev7d) }
    var redemptionRate: Int? {
        guard let issued = rewardsIssued30d, issued > 0, let red = rewardsRedeemed30d else { return nil }
        return Int((Double(red) / Double(issued) * 100).rounded())
    }
}

/// One cell of venue_hourly_heatmap (busiest times).
struct HeatCell: Decodable, Identifiable {
    let weekday: Int   // 0=Sun … 6=Sat
    let hour: Int
    let count: Int
    var id: String { "\(weekday)-\(hour)" }
    var weekdayLabel: String { ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][max(0, min(6, weekday))] }
}

/// One day of venue_daily_stats.
struct DailyStat: Decodable, Identifiable {
    let day: String
    let stamps: Int?
    let rewards: Int?
    let redemptions: Int?
    let newMembers: Int?
    var id: String { day }

    /// Parsed date for charting (Dubai).
    var date: Date {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier: "Asia/Dubai")
        return f.date(from: day) ?? Date()
    }
}

struct ManagerInviteResult: Decodable {
    let email: String?
    let tempPassword: String?
    let emailed: Bool?
}

/// A `staff_shifts` row (plain table CRUD).
struct ShiftCell: Decodable, Identifiable, Hashable {
    let id: String
    let staffId: String
    let workDate: String
    let startTime: String?
    let endTime: String?
    let isOff: Bool?
    let leaveType: String?
    let unpaidBreakMinutes: Int?

    var off: Bool { isOff ?? false }
    var timeLabel: String {
        if off { return leaveType == "weekly_off" ? "Off" : (leaveType?.capitalized ?? "Off") }
        let s = ShiftCell.trimSeconds(startTime)
        let e = ShiftCell.trimSeconds(endTime)
        if let s, let e { return "\(s) – \(e)" }
        return "—"
    }
    static func trimSeconds(_ t: String?) -> String? {
        guard let t else { return nil }
        let parts = t.split(separator: ":")
        return parts.count >= 2 ? "\(parts[0]):\(parts[1])" : t
    }
}

/// One row from `owner_attendance_detail`.
struct AttendanceRow: Decodable, Identifiable, Hashable {
    let kind: String?              // entry | no_show
    let entryId: String?
    let staffId: String?
    let name: String?
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
    let status: String?            // open | closed | auto_closed | no_show
    let source: String?
    let shiftStart: String?
    let shiftEnd: String?

    var id: String { entryId ?? "\(staffId ?? "?")-\(workDate ?? "?")" }
    var isOpen: Bool { status == "open" }
    var isNoShow: Bool { status == "no_show" || kind == "no_show" }
}

/// One row from `owner_clockin_reports`.
struct ClockinReportRow: Decodable, Identifiable, Hashable {
    let id: String
    let staffId: String?
    let staffName: String?
    let reportedAt: String?
    let note: String?
    let kind: String?              // missing_clockin | attendance_issue
    let entryId: String?
    let entryDate: String?
}

// MARK: - Settings

struct ProgramRule: Decodable, Hashable {
    let stampsRequired: Int?
    let rewardText: String?
    let dailyCap: Int?
    let expiryDays: Int?
    let graceDays: Int?
}

struct BrandingBlob: Codable, Hashable {
    var logoUrl: String?
    var googleReviewUrl: String?
}

struct VenueConfig: Decodable, Hashable {
    let loyaltyMode: String?
    let pointsRate: Double?
    let repeatStampApprovalMinutes: Int?
    let staffBonusEnabled: Bool?
    let birthdayGift: String?
    let birthdayGiftCount: Int?
    let birthdayGiftLabel: String?
    let clockCodeIntervalMinutes: Int?
    let otPayPolicy: String?
    let msgQuietStart: Int?
    let msgQuietEnd: Int?
    let msgFrequencyCap: Int?
    let weekendDays: [Int]?
    let branding: BrandingBlob?
}

struct RewardItem: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let pointsCost: Int?
    let active: Bool?
    let sort: Int?
}

struct Promotion: Decodable, Identifiable, Hashable {
    let id: String
    let label: String?
    let multiplier: Int?
    let startsAt: String?
    let endsAt: String?
    let active: Bool?
    let recurrence: String?
    let weekdays: [Int]?
    let dailyStart: String?
    let dailyEnd: String?
}

struct CreateVenueResult: Decodable {
    let result: String?
    let venueId: String?
    let cap: Int?
}

// MARK: - Campaigns

struct MerchantPlan: Decodable {
    let planTier: String?
    let billingStatus: String?
    let marketingMsgsUsed: Int?

    /// Campaigns require Standard+ AND an active paid plan.
    var canUseCampaigns: Bool {
        let rank = ["starter": 0, "standard": 1, "multi": 2]
        return (rank[planTier ?? "starter"] ?? 0) >= 1 && billingStatus == "active"
    }

    /// Monthly campaign (marketing) allowance for the plan — the soft cap.
    var campaignAllowance: Int {
        switch planTier {
        case "multi": return 1800
        case "standard": return 600
        default: return 200
        }
    }

    /// Campaign sends still available this month.
    var campaignsRemaining: Int {
        max(0, campaignAllowance - (marketingMsgsUsed ?? 0))
    }
}

struct CampaignSegmentDef: Codable, Hashable {
    var all: Bool?
    var daysInactive: Int?
}

struct CampaignRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let status: String?
    let segmentDef: CampaignSegmentDef?
    let scheduledAt: String?
    let createdAt: String?

    var audienceLabel: String {
        if segmentDef?.all == true { return "All members" }
        if let d = segmentDef?.daysInactive { return "Lapsed \(d)d+" }
        return "—"
    }
}

struct TemplateRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let language: String?
    let status: String?
    var isApproved: Bool { status == "approved" }
}

struct EnqueueResult: Decodable {
    let result: String?
    let enqueued: Int?
    let remainingAllowance: Int?
}

// MARK: - Support

struct SupportTicket: Decodable, Identifiable, Hashable {
    let id: String
    let subject: String?
    let status: String?
    let lastMessageAt: String?
    let lastMessagePreview: String?
    let ownerLastReadAt: String?
    let createdAt: String?

    var isClosed: Bool { status == "resolved" || status == "closed" }
    var unread: Bool {
        guard let last = lastMessageAt else { return false }
        guard let read = ownerLastReadAt else { return true }
        return last > read
    }
}

struct SupportMessage: Decodable, Identifiable, Hashable {
    let id: String
    let senderRole: String?
    let body: String?
    let createdAt: String?
    var isOwner: Bool { senderRole == "owner" }
}

// MARK: - Payroll

struct PayConfig: Decodable, Identifiable, Hashable {
    let staffId: String
    let payType: String?
    let baseRate: Double?
    let overtimeMultiplier: Double?
    let currency: String?
    let paydayDom: Int?
    let deductAbsences: Bool?
    let premiumMultiplier: Double?
    var id: String { staffId }
}

struct Payslip: Decodable, Identifiable, Hashable {
    let id: String
    let staffId: String
    let periodMonth: String?
    let regularMinutes: Int?
    let overtimeMinutes: Int?
    let premiumMinutes: Int?
    let premiumAmount: Double?
    let deductionAmount: Double?
    let grossAmount: Double?
    let adjustmentTotal: Double?
    let currency: String?
    let status: String?
    let expectedPayDate: String?
    let paidAt: String?
    let onTime: Bool?

    var net: Double { (grossAmount ?? 0) + (adjustmentTotal ?? 0) }
}

struct PayslipAdjustment: Decodable, Identifiable, Hashable {
    let id: String
    let payslipId: String
    let label: String
    let amount: Double
    let note: String?
}

struct AccessRequestRow: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String?          // out_of_hours | overtime | device_reset
    let reason: String?
    let requestedAt: String?
    let staffName: String?

    var kindLabel: String {
        switch kind {
        case "out_of_hours": return String(localized: "access.ooh", defaultValue: "Out of hours")
        case "overtime":     return String(localized: "access.ot", defaultValue: "Overtime")
        case "device_reset": return String(localized: "access.device", defaultValue: "Device reset")
        default:             return kind ?? "Request"
        }
    }
}
