//
//  StaffAuthViewModel.swift
//  ZUBUN
//
//  Drives PIN login + first-time onboarding (spec B1/B2). On success it persists
//  the bearer session so the device can resume staff mode.
//

import Foundation
import Observation

@MainActor
@Observable
final class StaffAuthViewModel {
    var venueID = ""
    var pin = ""
    var confirmPin = ""
    var isLoading = false
    var errorMessage: String?

    private let service = StaffService()
    private let session = SessionStore.shared

    init() { venueID = session.lastStaffVenueID ?? "" }   // returning staff: PIN-only

    /// This device already knows its venue → show PIN-only sign-in.
    var hasRememberedVenue: Bool { session.lastStaffVenueID != nil }
    var rememberedName: String? { session.lastStaffName }

    var canSubmitLogin: Bool {
        QRParser.isUUID(venueID.trimmingCharacters(in: .whitespaces)) && Validation.isValidPIN(pin)
    }

    /// Forget the bound venue (e.g. this is a different person/venue on the device).
    func useDifferentVenue() {
        session.forgetStaffVenue()
        venueID = ""; pin = ""; errorMessage = nil
    }

    func login() async {
        guard canSubmitLogin else {
            errorMessage = ResultCode.invalidPin.userMessage
            return
        }
        await run {
            let res = try await service.login(venueID: venueID.trimmingCharacters(in: .whitespaces), pin: pin)
            try persist(res)
        }
    }

    func onboard(token: String) async {
        guard Validation.isValidPIN(pin), pin == confirmPin else {
            errorMessage = pin == confirmPin ? ResultCode.invalidPin.userMessage
                : String(localized: "onboard.mismatch", defaultValue: "PINs don't match")
            return
        }
        await run {
            let res = try await service.onboard(token: token, pin: pin)
            try persist(res)
        }
    }

    func setVenueFromScan(_ code: ScannedCode) {
        if case let .joinVenue(id) = code { venueID = id }
    }

    private func persist(_ res: StaffAuthResponse) throws {
        guard res.ok else { throw APIError.result(.invalidCredentials) }
        session.saveStaff(StaffSession(
            token: res.token,
            staffID: res.staffId,
            displayName: res.displayName,
            venueID: res.venueId,
            expiresAt: DubaiDate.parseISO(res.expiresAt)
        ))
        // Remember the venue so the next sign-in on this device is PIN-only.
        session.lastStaffVenueID = res.venueId
        session.lastStaffName = res.displayName
    }

    private func run(_ work: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await work()
        } catch let APIError.result(code) {
            errorMessage = code.userMessage
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
