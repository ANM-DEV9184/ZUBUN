//
//  OwnerService.swift
//  ZUBUN
//
//  Owner auth (Supabase email/password) + dashboard reads/writes, wired to the
//  REAL backend contracts (verified against dayem-starter `supabase/migrations`
//  and `src/app/api/dashboard`):
//   • owner_consolidated_kpis(p_merchant_id)  → merchant-wide KPIs
//   • owner_stamp_approvals(p_venue_id)       → pending repeat-stamp queue
//   • decide_stamp_approval(p_request_id, p_approve, p_app_secret)
//  All are granted to `authenticated` and self-guard via SECURITY DEFINER, so we
//  call them directly through PostgREST with the owner's JWT.
//

import Foundation

struct OwnerService {
    var api = APIClient()
    var supabase: SupabaseService = .shared
    var session: SessionStore = .shared

    func signIn(email: String, password: String) async throws {
        let token = try await supabase.ownerSignIn(email: email, password: password)
        session.saveOwnerToken(token)
    }

    func signOut() async {
        await supabase.signOut()
        session.clearOwner()
    }

    /// Merchant id is carried as an app_metadata claim in the owner JWT.
    var merchantID: String? {
        session.ownerToken.flatMap(JWTPayload.merchantID(from:))
    }

    /// Merchant-wide KPI overview (RPC `owner_consolidated_kpis`).
    func kpis() async throws -> OwnerKPIs {
        guard let merchantID else { throw APIError.notConfigured("No merchant_id in session.") }
        struct Params: Encodable { let pMerchantId: String }
        return try await supabase.rpc("owner_consolidated_kpis",
                                      params: Params(pMerchantId: merchantID),
                                      accessToken: session.ownerToken)
    }

    /// Pending repeat-stamp approvals for one venue (RPC `owner_stamp_approvals`).
    func stampApprovals(venueID: String) async throws -> [StampApproval] {
        struct Params: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_stamp_approvals",
                                      params: Params(pVenueId: venueID),
                                      accessToken: session.ownerToken)
    }

    /// Approve/deny a repeat stamp (spec C3).
    ///
    /// Routed through the bearer server route so the server HMAC_SECRET encrypts
    /// the reward token when an approval *completes* a card (the app can't hold
    /// the secret). The RPC still self-guards on venue ownership.
    @discardableResult
    func decideStampApproval(requestID: String, approve: Bool) async throws -> DecideResult {
        struct Body: Encodable { let requestId: String; let approve: Bool }
        return try await api.post("/api/owner/stamp-approval",
                                  body: Body(requestId: requestID, approve: approve), auth: .owner)
    }
}

struct DecideResult: Decodable {
    let ok: Bool?
    let result: String?
}

struct GrantResult: Decodable {
    let result: String?
    let stampsCount: Int?
    let stampsRequired: Int?
    let rewardText: String?
}

// MARK: - Batch 1: venues, members, approval queues

extension OwnerService {

    private static let membersPageSize = 25

    /// The owner's venues (id/name/status) for the switcher — RLS-scoped select.
    func venues() async throws -> [OwnerVenue] {
        try await supabase.restGet("venues",
                                   query: [
                                       .init(name: "select", value: "id,name,status"),
                                       .init(name: "order", value: "name.asc"),
                                   ],
                                   accessToken: session.ownerToken)
    }

    /// Members roster for a venue, with optional name/phone search + paging.
    func members(venueID: String, search: String = "", offset: Int = 0) async throws -> [MemberRow] {
        let q = search.trimmingCharacters(in: .whitespaces)
        var items: [URLQueryItem] = [
            .init(name: "venue_id", value: "eq.\(venueID)"),
            .init(name: "order", value: "last_visit_at.desc.nullslast,created_at.desc"),
            .init(name: "limit", value: "\(Self.membersPageSize)"),
            .init(name: "offset", value: "\(offset)"),
        ]
        if q.isEmpty {
            items.append(.init(name: "select",
                               value: "id,card_state,stamps_count,tier,marketing_opt_in,last_visit_at,created_at,customers(phone_e164,name_optional)"))
        } else {
            items.append(.init(name: "select",
                               value: "id,card_state,stamps_count,tier,marketing_opt_in,last_visit_at,created_at,customers!inner(phone_e164,name_optional)"))
            items.append(.init(name: "customers.or",
                               value: "(phone_e164.ilike.*\(q)*,name_optional.ilike.*\(q)*)"))
        }
        return try await supabase.restGet("memberships", query: items, accessToken: session.ownerToken)
    }

    /// Stamp history for a membership (with the staff who issued each).
    func memberStamps(membershipID: String) async throws -> [MemberStamp] {
        try await supabase.restGet("stamps",
                                   query: [
                                       .init(name: "select", value: "id,created_at,fallback_flag,staff_users(display_name)"),
                                       .init(name: "membership_id", value: "eq.\(membershipID)"),
                                       .init(name: "order", value: "created_at.desc"),
                                       .init(name: "limit", value: "50"),
                                   ],
                                   accessToken: session.ownerToken)
    }

    /// Reward/redemption history for a membership.
    func memberRewards(membershipID: String) async throws -> [MemberReward] {
        try await supabase.restGet("redemption_tokens",
                                   query: [
                                       .init(name: "select", value: "id,status,created_at,consumed_at,expires_at,void_reason"),
                                       .init(name: "membership_id", value: "eq.\(membershipID)"),
                                       .init(name: "order", value: "created_at.desc"),
                                       .init(name: "limit", value: "20"),
                                   ],
                                   accessToken: session.ownerToken)
    }

    /// Grant bonus stamps (owner source — bypasses the daily cap).
    ///
    /// Routed through the bearer server route so a grant that *completes* a card
    /// mints the encrypted reward token with the server HMAC_SECRET.
    @discardableResult
    func grantStamps(membershipID: String, count: Int, reason: String) async throws -> GrantResult {
        struct Body: Encodable { let membershipId: String; let count: Int; let reason: String }
        return try await api.post("/api/owner/grant-stamps",
                                  body: Body(membershipId: membershipID, count: count, reason: reason), auth: .owner)
    }

    // MARK: Approval queue readers

    func leaveRequests(venueID: String) async throws -> [LeaveRequestRow] {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_leave_requests", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }
    func dayoffRequests(venueID: String) async throws -> [DayoffRequestRow] {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_dayoff_requests", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }
    func shiftSwaps(venueID: String) async throws -> [ShiftSwapRow] {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_shift_swaps", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }
    func accessRequests(venueID: String) async throws -> [AccessRequestRow] {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_access_requests", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }

    // MARK: Approval decisions (direct RPC, owner JWT)

    @discardableResult
    func decideLeave(id: String, approve: Bool) async throws -> DecideResult {
        struct P: Encodable { let pRequestId: String; let pApprove: Bool }
        return try await supabase.rpc("decide_leave_request", params: P(pRequestId: id, pApprove: approve), accessToken: session.ownerToken)
    }
    @discardableResult
    func decideDayoff(id: String, approve: Bool) async throws -> DecideResult {
        struct P: Encodable { let pRequestId: String; let pApprove: Bool }
        return try await supabase.rpc("decide_dayoff_change", params: P(pRequestId: id, pApprove: approve), accessToken: session.ownerToken)
    }
    @discardableResult
    func decideSwap(id: String, approve: Bool) async throws -> DecideResult {
        struct P: Encodable { let pId: String; let pApprove: Bool }
        return try await supabase.rpc("decide_shift_swap", params: P(pId: id, pApprove: approve), accessToken: session.ownerToken)
    }
    @discardableResult
    func decideAccess(id: String, approve: Bool, windowMinutes: Int = 120) async throws -> DecideResult {
        struct P: Encodable { let pRequestId: String; let pApprove: Bool; let pWindowMinutes: Int }
        return try await supabase.rpc("decide_staff_access",
                                      params: P(pRequestId: id, pApprove: approve, pWindowMinutes: windowMinutes),
                                      accessToken: session.ownerToken)
    }
}

// MARK: - Batch 2: rota + live attendance

/// Body for a `staff_shifts` insert (nil optionals are omitted by the encoder).
private struct ShiftInsert: Encodable {
    let staffId: String
    let venueId: String
    let workDate: String
    let startTime: String?
    let endTime: String?
    let isOff: Bool
    let leaveType: String?
    let unpaidBreakMinutes: Int
}

extension OwnerService {

    // MARK: Rota (plain staff_shifts CRUD under RLS)

    func venueStaff(venueID: String) async throws -> [OwnerStaff] {
        try await supabase.restGet("staff_users",
                                   query: [
                                       .init(name: "select", value: "id,display_name,status,onboarded"),
                                       .init(name: "venue_id", value: "eq.\(venueID)"),
                                       .init(name: "order", value: "display_name.asc"),
                                   ],
                                   accessToken: session.ownerToken)
    }

    /// Add a pending staffer; returns the onboarding invite link to share.
    func addStaff(venueID: String, name: String) async throws -> StaffInvite {
        struct Body: Encodable { let venueId: String; let displayName: String }
        return try await api.post("/api/owner/staff-add",
                                  body: Body(venueId: venueID, displayName: name), auth: .owner)
    }

    /// Suspend / reactivate a staffer (self-guarded RPC).
    @discardableResult
    func setStaffStatus(staffID: String, status: String) async throws -> DecideResult {
        struct P: Encodable { let pStaffId: String; let pStatus: String }
        return try await supabase.rpc("set_staff_status",
                                      params: P(pStaffId: staffID, pStatus: status), accessToken: session.ownerToken)
    }

    // MARK: - Managers (owner-only, Standard/Multi)

    func managers() async throws -> [Manager] {
        let res: ManagersResponse = try await api.get("/api/owner/managers", auth: .owner)
        return res.managers
    }

    func inviteManager(email: String) async throws -> ManagerInviteResult {
        struct Body: Encodable { let email: String }
        return try await api.post("/api/owner/managers", body: Body(email: email), auth: .owner)
    }

    func removeManager(authUserID: String) async throws {
        struct Body: Encodable { let authUserId: String }
        struct OK: Decodable {}
        let _: OK = try await api.delete("/api/owner/managers", body: Body(authUserId: authUserID), auth: .owner)
    }

    func shifts(venueID: String, from: String, to: String) async throws -> [ShiftCell] {
        try await supabase.restGet("staff_shifts",
                                   query: [
                                       .init(name: "select", value: "id,staff_id,work_date,start_time,end_time,is_off,leave_type,unpaid_break_minutes"),
                                       .init(name: "venue_id", value: "eq.\(venueID)"),
                                       .init(name: "work_date", value: "gte.\(from)"),
                                       .init(name: "work_date", value: "lte.\(to)"),
                                       .init(name: "order", value: "work_date.asc"),
                                   ],
                                   accessToken: session.ownerToken)
    }

    /// Replace whatever is on a staffer's day with a working shift.
    func setWorkingShift(venueID: String, staffID: String, date: String,
                         start: String, end: String, breakMinutes: Int) async throws {
        try await clearDay(staffID: staffID, date: date)
        try await supabase.restInsert("staff_shifts",
                                      body: ShiftInsert(staffId: staffID, venueId: venueID, workDate: date,
                                                        startTime: start, endTime: end, isOff: false,
                                                        leaveType: nil, unpaidBreakMinutes: breakMinutes),
                                      accessToken: session.ownerToken)
    }

    /// Replace a staffer's day with an off/leave marker.
    func setOffDay(venueID: String, staffID: String, date: String, leaveType: String) async throws {
        try await clearDay(staffID: staffID, date: date)
        try await supabase.restInsert("staff_shifts",
                                      body: ShiftInsert(staffId: staffID, venueId: venueID, workDate: date,
                                                        startTime: nil, endTime: nil, isOff: true,
                                                        leaveType: leaveType, unpaidBreakMinutes: 0),
                                      accessToken: session.ownerToken)
    }

    func clearDay(staffID: String, date: String) async throws {
        try await supabase.restDelete("staff_shifts",
                                      query: [
                                          .init(name: "staff_id", value: "eq.\(staffID)"),
                                          .init(name: "work_date", value: "eq.\(date)"),
                                      ],
                                      accessToken: session.ownerToken)
    }

    func deleteShift(id: String) async throws {
        try await supabase.restDelete("staff_shifts",
                                      query: [.init(name: "id", value: "eq.\(id)")],
                                      accessToken: session.ownerToken)
    }

    /// Copy the previous week's working shifts forward 7 days (skips duplicates).
    func copyLastWeek(venueID: String, currentWeekStart: String, prevWeekStart: String, prevWeekEnd: String) async throws {
        let prev = try await shifts(venueID: venueID, from: prevWeekStart, to: prevWeekEnd)
        let rows: [ShiftInsert] = prev.compactMap { cell in
            guard !cell.off, let start = cell.startTime, let end = cell.endTime,
                  let next = DubaiDate.addDays(7, toDateString: cell.workDate) else { return nil }
            return ShiftInsert(staffId: cell.staffId, venueId: venueID, workDate: next,
                               startTime: start, endTime: end, isOff: false,
                               leaveType: nil, unpaidBreakMinutes: cell.unpaidBreakMinutes ?? 0)
        }
        guard !rows.isEmpty else { return }
        try await supabase.restInsert("staff_shifts", body: rows,
                                      upsertOnConflict: "staff_id,work_date,start_time",
                                      ignoreDuplicates: true,
                                      accessToken: session.ownerToken)
    }

    // MARK: Live attendance

    func attendanceDetail(venueID: String, from: String, to: String) async throws -> [AttendanceRow] {
        struct P: Encodable { let pVenueId: String; let pFrom: String; let pTo: String }
        return try await supabase.rpc("owner_attendance_detail",
                                      params: P(pVenueId: venueID, pFrom: from, pTo: to),
                                      accessToken: session.ownerToken)
    }

    func clockinReports(venueID: String) async throws -> [ClockinReportRow] {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("owner_clockin_reports", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }

    @discardableResult
    func deleteEntry(id: String) async throws -> DecideResult {
        struct P: Encodable { let pEntryId: String }
        return try await supabase.rpc("owner_delete_time_entry", params: P(pEntryId: id), accessToken: session.ownerToken)
    }

    @discardableResult
    func resolveClockinReport(id: String) async throws -> DecideResult {
        struct P: Encodable { let pReportId: String }
        return try await supabase.rpc("owner_resolve_clockin_report", params: P(pReportId: id), accessToken: session.ownerToken)
    }

    /// The venue's live 20-minute counter code (RPC returns a text scalar).
    func clockCode(venueID: String) async throws -> String {
        struct P: Encodable { let pVenueId: String }
        return try await supabase.rpc("dayem_venue_clock_code", params: P(pVenueId: venueID), accessToken: session.ownerToken)
    }

    /// Create a manual time entry (spec C8). clock-out/note are optional (null).
    @discardableResult
    func createTimeEntry(staffID: String, workDate: String, clockInISO: String,
                         clockOutISO: String?, note: String?) async throws -> DecideResult {
        let params: [String: JSONParam] = [
            "p_staff_id": .string(staffID),
            "p_work_date": .string(workDate),
            "p_clock_in_at": .string(clockInISO),
            "p_clock_out_at": .optString(clockOutISO),
            "p_note": .optString(note),
        ]
        return try await supabase.rpc("owner_create_time_entry", params: params, accessToken: session.ownerToken)
    }

    /// Adjust an existing time entry (spec C8). All fields except id are optional.
    @discardableResult
    func adjustTimeEntry(entryID: String, clockInISO: String?, clockOutISO: String?,
                         status: String?, overtimeStatus: String?, note: String?) async throws -> DecideResult {
        let params: [String: JSONParam] = [
            "p_entry_id": .string(entryID),
            "p_clock_in_at": .optString(clockInISO),
            "p_clock_out_at": .optString(clockOutISO),
            "p_status": .optString(status),
            "p_overtime_status": .optString(overtimeStatus),
            "p_note": .optString(note),
        ]
        return try await supabase.rpc("owner_adjust_time_entry", params: params, accessToken: session.ownerToken)
    }
}
