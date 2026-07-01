//
//  ResultCode.swift
//  ZUBUN
//
//  Every loyalty / clock / redeem / join RPC returns a string `result`.
//  This is the single mapping from code -> user-facing copy + UI tone.
//  (Spec Part III §5.)
//

import Foundation

/// Visual tone for result overlays / toasts.
enum ResultTone {
    case success   // green
    case warning   // amber
    case reward    // celebratory
    case error     // red
    case info      // neutral
}

enum ResultCode: String, Codable, Equatable, Sendable {
    // Stamp
    case stamped
    case duplicate
    case dailyCapReached = "daily_cap_reached"
    case needsOwnerApproval = "needs_owner_approval"
    case rewardIssued = "reward_issued"
    case noMembership = "no_membership"
    case noProgramRule = "no_program_rule"
    case staffNotAuthorized = "staff_not_authorized"
    case programPaused = "program_paused"
    case pointsMode = "points_mode"
    case bonusDisabled = "bonus_disabled"

    // Points
    case accrued
    case insufficientPoints = "insufficient_points"
    case notPointsMode = "not_points_mode"
    case invalidCount = "invalid_count"

    // Break
    case onBreak = "on_break"
    case breakEnded = "break_ended"
    case alreadyOnBreak = "already_on_break"
    case notOnBreak = "not_on_break"

    // Redeem
    case redeemed
    case alreadyUsed = "already_used"
    case voided
    case expired
    case wrongVenue = "wrong_venue"

    // Clock / attendance
    case clockedIn = "clocked_in"
    case clockedOut = "clocked_out"
    case badCode = "bad_code"
    case outsideShift = "outside_shift"
    case deviceMismatch = "device_mismatch"
    case alreadyClockedIn = "already_clocked_in"
    case notClockedIn = "not_clocked_in"

    // Join / enrollment
    case enrolled
    case alreadyMember = "already_member"
    case venueFull = "venue_full"
    case erasedCustomer = "erased_customer"
    case invalidPhone = "invalid_phone"
    case invalidVenue = "invalid_venue"

    // Auth
    case ok
    case invalidCredentials = "invalid_credentials"
    case tooManyAttempts = "too_many_attempts"
    case alreadyOnboarded = "already_onboarded"
    case invalidPin = "invalid_pin"
    case invalidInvite = "invalid_invite"

    // Customer generic successes
    case saved
    case optedOut = "opted_out"
    case pendingErasure = "pending_erasure"
    case erased

    // Requests / generic
    case requested
    case overlap
    case invalid
    case notOff = "not_off"
    case alreadyOff = "already_off"
    case targetBusy = "target_busy"
    case customerNotFound = "customer_not_found"

    /// Codes the parser hasn't seen.
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ResultCode(rawValue: raw) ?? .unknown
    }

    var tone: ResultTone {
        switch self {
        case .stamped, .accrued, .redeemed, .clockedIn, .clockedOut, .enrolled, .alreadyMember, .ok, .requested,
             .saved, .optedOut, .pendingErasure, .erased, .onBreak, .breakEnded:
            return .success
        case .rewardIssued:
            return .reward
        case .duplicate, .dailyCapReached, .needsOwnerApproval, .alreadyClockedIn, .notClockedIn,
             .outsideShift, .overlap, .alreadyOff, .notOff:
            return .warning
        case .pointsMode, .programPaused, .badCode, .targetBusy, .invalid:
            return .info
        default:
            return .error
        }
    }

    /// Localised user copy. Arabic strings are resolved via Localizable; here we
    /// return the key so SwiftUI's `Text` / `String(localized:)` can localise.
    var userMessage: String {
        switch self {
        case .stamped:             return String(localized: "result.stamped", defaultValue: "Stamp added")
        case .duplicate:           return String(localized: "result.duplicate", defaultValue: "Already stamped just now")
        case .dailyCapReached:     return String(localized: "result.daily_cap", defaultValue: "Daily stamp limit reached")
        case .needsOwnerApproval:  return String(localized: "result.needs_approval", defaultValue: "Sent to owner for approval")
        case .rewardIssued:        return String(localized: "result.reward", defaultValue: "Reward earned! 🎉")
        case .noMembership:        return String(localized: "result.no_membership", defaultValue: "Customer is not a member")
        case .noProgramRule:       return String(localized: "result.no_rule", defaultValue: "No active loyalty program")
        case .staffNotAuthorized:  return String(localized: "result.not_authorized", defaultValue: "You're not authorised at this venue")
        case .programPaused:       return String(localized: "result.paused", defaultValue: "Program is paused")
        case .pointsMode:          return String(localized: "result.points_mode", defaultValue: "This venue uses points")
        case .bonusDisabled:       return String(localized: "result.bonus_disabled", defaultValue: "Bonus stamps are disabled")
        case .accrued:             return String(localized: "result.accrued", defaultValue: "Points added")
        case .insufficientPoints:  return String(localized: "result.insufficient", defaultValue: "Not enough points")
        case .notPointsMode:       return String(localized: "result.not_points", defaultValue: "This venue isn't in points mode")
        case .invalidCount:        return String(localized: "result.invalid_count", defaultValue: "Invalid stamp count")
        case .onBreak:             return String(localized: "result.on_break", defaultValue: "Break started")
        case .breakEnded:          return String(localized: "result.break_ended", defaultValue: "Break ended")
        case .alreadyOnBreak:      return String(localized: "result.already_break", defaultValue: "Already on a break")
        case .notOnBreak:          return String(localized: "result.not_break", defaultValue: "You're not on a break")
        case .redeemed:            return String(localized: "result.redeemed", defaultValue: "Reward redeemed")
        case .alreadyUsed:         return String(localized: "result.already_used", defaultValue: "Reward already used")
        case .voided:              return String(localized: "result.voided", defaultValue: "Reward was voided")
        case .expired:             return String(localized: "result.expired", defaultValue: "Reward expired")
        case .wrongVenue:          return String(localized: "result.wrong_venue", defaultValue: "Reward is for another venue")
        case .clockedIn:           return String(localized: "result.clocked_in", defaultValue: "Clocked in")
        case .clockedOut:          return String(localized: "result.clocked_out", defaultValue: "Clocked out")
        case .badCode:             return String(localized: "result.bad_code", defaultValue: "Code is wrong or expired")
        case .outsideShift:        return String(localized: "result.outside_shift", defaultValue: "You're outside your shift window")
        case .deviceMismatch:      return String(localized: "result.device_mismatch", defaultValue: "This isn't your registered device")
        case .alreadyClockedIn:    return String(localized: "result.already_in", defaultValue: "You're already clocked in")
        case .notClockedIn:        return String(localized: "result.not_in", defaultValue: "You're not clocked in")
        case .enrolled:            return String(localized: "result.enrolled", defaultValue: "Joined! Card added")
        case .alreadyMember:       return String(localized: "result.already_member", defaultValue: "You're already a member")
        case .venueFull:           return String(localized: "result.venue_full", defaultValue: "This venue is at capacity")
        case .erasedCustomer:      return String(localized: "result.erased", defaultValue: "This number can't be re-enrolled")
        case .invalidPhone:        return String(localized: "result.invalid_phone", defaultValue: "Enter a valid phone number")
        case .invalidVenue:        return String(localized: "result.invalid_venue", defaultValue: "Venue not found")
        case .invalidCredentials:  return String(localized: "result.invalid_creds", defaultValue: "Wrong PIN")
        case .tooManyAttempts:     return String(localized: "result.too_many", defaultValue: "Too many attempts. Try again soon")
        case .alreadyOnboarded:    return String(localized: "result.onboarded", defaultValue: "Already set up — just log in")
        case .invalidPin:          return String(localized: "result.invalid_pin", defaultValue: "PIN must be 4–8 digits")
        case .invalidInvite:       return String(localized: "result.invalid_invite", defaultValue: "This invite link is invalid")
        case .saved:               return String(localized: "result.saved", defaultValue: "Saved")
        case .optedOut:            return String(localized: "result.opted_out", defaultValue: "You're opted out of marketing")
        case .pendingErasure:      return String(localized: "result.pending_erasure", defaultValue: "Account deletion scheduled")
        case .erased:              return String(localized: "result.erased_done", defaultValue: "Your data has been erased")
        case .requested:           return String(localized: "result.requested", defaultValue: "Request sent")
        case .overlap:             return String(localized: "result.overlap", defaultValue: "Overlaps an existing request")
        case .notOff:              return String(localized: "result.not_off", defaultValue: "That isn't a day off")
        case .alreadyOff:          return String(localized: "result.already_off", defaultValue: "That day is already off")
        case .targetBusy:          return String(localized: "result.target_busy", defaultValue: "That day already has a shift or leave")
        case .customerNotFound:    return String(localized: "result.customer_not_found", defaultValue: "No customer with that number")
        case .ok:                  return String(localized: "result.ok", defaultValue: "Done")
        case .invalid, .unknown:   return String(localized: "result.invalid", defaultValue: "Something went wrong")
        }
    }
}
