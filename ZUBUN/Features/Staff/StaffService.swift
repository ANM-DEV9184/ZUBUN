//
//  StaffService.swift
//  ZUBUN
//
//  All staff REST calls (spec §8). Auth = staff bearer JWT + X-Device-Id, except
//  login/onboard which send only the device id.
//

import Foundation

struct StaffService {
    var api = APIClient()

    // MARK: - Auth

    func login(venueID: String, pin: String) async throws -> StaffAuthResponse {
        struct Body: Encodable { let venueId: String; let pin: String }
        return try await api.post("/api/auth/staff-login",
                                  body: Body(venueId: venueID, pin: pin),
                                  auth: .deviceOnly)
    }

    func onboard(token: String, pin: String) async throws -> StaffAuthResponse {
        struct Body: Encodable { let token: String; let pin: String }
        return try await api.post("/api/auth/staff-onboard",
                                  body: Body(token: token, pin: pin),
                                  auth: .deviceOnly)
    }

    func logout() async {
        struct Body: Encodable {}
        _ = try? await api.postResult("/api/auth/staff-logout", body: Body(), auth: .staff)
    }

    // MARK: - Loyalty

    func stamp(qr: String, amount: Int? = nil) async throws -> StampResult {
        struct Body: Encodable { let qr: String; let amount: Int? }
        return try await api.post("/api/staff/stamp", body: Body(qr: qr, amount: amount), auth: .staff)
    }

    func stampFallback(phone: String, amount: Int? = nil) async throws -> StampResult {
        struct Body: Encodable { let phone: String; let amount: Int? }
        return try await api.post("/api/staff/stamp-fallback", body: Body(phone: phone, amount: amount), auth: .staff)
    }

    func redeem(qr: String) async throws -> RedeemResult {
        struct Body: Encodable { let qr: String }
        return try await api.post("/api/staff/redeem", body: Body(qr: qr), auth: .staff)
    }

    func bonus(qr: String, count: Int) async throws -> StampResult {
        struct Body: Encodable { let qr: String; let count: Int }
        return try await api.post("/api/staff/bonus", body: Body(qr: qr, count: count), auth: .staff)
    }

    // MARK: - Clock / attendance

    func clockIn(code: String) async throws -> ClockResult {
        struct Body: Encodable { let code: String }
        return try await api.post("/api/staff/clock-in", body: Body(code: code), auth: .staff)
    }

    /// Clock-out no longer needs the rotating code — the selfie is the presence
    /// proof. Returns early_leave_minutes so the app can warn on an early exit.
    func clockOut() async throws -> ClockResult {
        struct Body: Encodable {}
        return try await api.post("/api/staff/clock-out", body: Body(), auth: .staff)
    }

    func breakAction(_ action: String, code: String) async throws -> ResultEnvelope {
        struct Body: Encodable { let action: String; let code: String }
        return try await api.postResult("/api/staff/break", body: Body(action: action, code: code), auth: .staff)
    }

    /// `photo` is a JPEG ≤600KB encoded as a data URL.
    func clockPhoto(which: String, jpeg: Data) async throws -> ResultEnvelope {
        struct Body: Encodable { let which: String; let photo: String }
        let dataURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        return try await api.postResult("/api/staff/clock-photo", body: Body(which: which, photo: dataURL), auth: .staff)
    }

    // MARK: - Requests

    func requestAccess(kind: String, reason: String?) async throws -> ResultEnvelope {
        struct Body: Encodable { let kind: String; let reason: String? }
        return try await api.postResult("/api/staff/request-access", body: Body(kind: kind, reason: reason), auth: .staff)
    }

    func requestLeave(from: String, to: String, leaveType: String, reason: String?) async throws -> ResultEnvelope {
        struct Body: Encodable { let from: String; let to: String; let leaveType: String; let reason: String? }
        return try await api.postResult("/api/staff/request-leave",
                                        body: Body(from: from, to: to, leaveType: leaveType, reason: reason),
                                        auth: .staff)
    }

    func requestDayoffChange(from: String, to: String, reason: String?) async throws -> ResultEnvelope {
        struct Body: Encodable { let from: String; let to: String; let reason: String? }
        return try await api.postResult("/api/staff/request-dayoff-change",
                                        body: Body(from: from, to: to, reason: reason), auth: .staff)
    }

    func swap(shiftID: String, toStaff: String, reason: String?) async throws -> ResultEnvelope {
        struct Body: Encodable { let shiftId: String; let toStaff: String; let reason: String? }
        return try await api.postResult("/api/staff/swap",
                                        body: Body(shiftId: shiftID, toStaff: toStaff, reason: reason), auth: .staff)
    }

    func reportMissingClockIn(note: String?) async throws -> ResultEnvelope {
        struct Body: Encodable { let note: String? }
        return try await api.postResult("/api/staff/report-missing-clockin", body: Body(note: note), auth: .staff)
    }

    func flagAttendance(entryID: String, note: String?) async throws -> ResultEnvelope {
        struct Body: Encodable { let entryId: String; let note: String? }
        return try await api.postResult("/api/staff/flag-attendance", body: Body(entryId: entryID, note: note), auth: .staff)
    }

    func changePIN(old: String, new: String) async throws -> ResultEnvelope {
        struct Body: Encodable { let oldPin: String; let newPin: String }
        return try await api.postResult("/api/staff/change-pin", body: Body(oldPin: old, newPin: new), auth: .staff)
    }

    func payslip(id: String, dispute: Bool, note: String?) async throws -> ResultEnvelope {
        struct Body: Encodable { let payslipId: String; let dispute: Bool; let note: String? }
        return try await api.postResult("/api/staff/payslip",
                                        body: Body(payslipId: id, dispute: dispute, note: note), auth: .staff)
    }

    // MARK: - Reads

    func shiftStats() async throws -> ShiftStats {
        try await api.get("/api/staff/shift-stats", auth: .staff)
    }

    /// The staffer's own upcoming schedule.
    func shifts() async throws -> [StaffShift] {
        let res: StaffShiftsResponse = try await api.get("/api/staff/shifts", auth: .staff)
        return res.shifts
    }
}
