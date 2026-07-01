//
//  CoreLogicTests.swift
//  ZUBUNTests
//
//  Deterministic unit tests for the pure logic layer (no network). MainActor
//  because the app module defaults to MainActor isolation.
//

import Testing
@testable import ZUBUN

@MainActor
struct ValidationTests {
    @Test func validE164() {
        #expect(Validation.isValidE164("+971501234567"))
        #expect(Validation.isValidE164("+14155552671"))
        #expect(!Validation.isValidE164("0501234567"))
        #expect(!Validation.isValidE164("+0501234567"))   // leading zero after +
        #expect(!Validation.isValidE164("abc"))
        #expect(!Validation.isValidE164("+12"))            // too short
    }

    @Test func pinRules() {
        #expect(Validation.isValidPIN("1234"))
        #expect(Validation.isValidPIN("12345678"))
        #expect(!Validation.isValidPIN("123"))             // too short
        #expect(!Validation.isValidPIN("123456789"))       // too long
        #expect(!Validation.isValidPIN("12a4"))
    }

    @Test func normalizeUAEPhone() {
        #expect(Validation.normalizeUAEPhone("0501234567") == "+971501234567")
        #expect(Validation.normalizeUAEPhone("501234567") == "+971501234567")
        #expect(Validation.normalizeUAEPhone("971501234567") == "+971501234567")
        #expect(Validation.normalizeUAEPhone("+971501234567") == "+971501234567")
        #expect(Validation.normalizeUAEPhone("00971501234567") == "+971501234567")
    }
}

@MainActor
struct QRParsingTests {
    @Test func customerAndReward() {
        #expect(QRParser.parse("dayem:c:abc.def") == .customer(qr: "dayem:c:abc.def"))
        #expect(QRParser.parse("dayem:r:rawtoken") == .reward(qr: "dayem:r:rawtoken"))
    }

    @Test func joinLinkAndUUID() {
        let uuid = "123e4567-e89b-12d3-a456-426614174000"
        #expect(QRParser.parse("https://zubun.io/j/\(uuid)") == .joinVenue(venueID: uuid))
        #expect(QRParser.parse("https://zubun.io/j/\(uuid)?ref=x") == .joinVenue(venueID: uuid))
        #expect(QRParser.parse(uuid) == .joinVenue(venueID: uuid))
    }

    @Test func unknown() {
        #expect(QRParser.parse("hello world") == .unknown(raw: "hello world"))
    }
}

@MainActor
struct ResultCodeTests {
    @Test func decodesKnownAndUnknown() {
        #expect(ResultCode(rawValue: "stamped") == .stamped)
        #expect(ResultCode(rawValue: "needs_owner_approval") == .needsOwnerApproval)
        #expect(ResultCode(rawValue: "opted_out") == .optedOut)
        #expect(ResultCode(rawValue: "totally_made_up") == nil)
    }

    @Test func tones() {
        #expect(ResultCode.stamped.tone == .success)
        #expect(ResultCode.rewardIssued.tone == .reward)
        #expect(ResultCode.duplicate.tone == .warning)
        #expect(ResultCode.noMembership.tone == .error)
    }
}

@MainActor
struct DubaiDateTests {
    @Test func ymdRoundTrip() {
        let s = "2026-07-01"
        let d = DubaiDate.date(fromYMD: s)
        #expect(d != nil)
        #expect(DubaiDate.ymdString(d!) == s)
    }

    @Test func addDaysAcrossMonth() {
        #expect(DubaiDate.addDays(1, toDateString: "2026-06-30") == "2026-07-01")
        #expect(DubaiDate.addDays(7, toDateString: "2026-07-01") == "2026-07-08")
        #expect(DubaiDate.addDays(-1, toDateString: "2026-07-01") == "2026-06-30")
    }

    @Test func weekStartIsMonday() {
        // 2026-07-01 is a Wednesday; its week start (Mon) is 2026-06-29.
        let wed = DubaiDate.date(fromYMD: "2026-07-01")!
        #expect(DubaiDate.ymdString(DubaiDate.weekStart(wed)) == "2026-06-29")
    }

    @Test func monthString() {
        let d = DubaiDate.date(fromYMD: "2026-07-01")!
        #expect(DubaiDate.monthString(d) == "2026-07")
    }
}

@MainActor
struct ModelTests {
    @Test func maskedPhone() {
        let m = MemberRow(id: "1", cardState: "active", stampsCount: 3, tier: .silver,
                          marketingOptIn: true, lastVisitAt: nil, createdAt: nil,
                          customers: MemberCustomer(phoneE164: "+971501234567", nameOptional: nil))
        #expect(m.maskedPhone == "•••• 4567")
        #expect(m.displayName == "+971501234567")
    }

    @Test func campaignGate() {
        #expect(MerchantPlan(planTier: "standard", billingStatus: "active").canUseCampaigns)
        #expect(MerchantPlan(planTier: "multi", billingStatus: "active").canUseCampaigns)
        #expect(!MerchantPlan(planTier: "starter", billingStatus: "active").canUseCampaigns)
        #expect(!MerchantPlan(planTier: "standard", billingStatus: "trialing").canUseCampaigns)
    }

    @Test func shiftCellLabel() {
        let off = ShiftCell(id: "1", staffId: "s", workDate: "2026-07-01", startTime: nil, endTime: nil,
                            isOff: true, leaveType: "weekly_off", unpaidBreakMinutes: 0)
        #expect(off.timeLabel == "Off")
        let work = ShiftCell(id: "2", staffId: "s", workDate: "2026-07-01", startTime: "09:00:00",
                             endTime: "17:00:00", isOff: false, leaveType: nil, unpaidBreakMinutes: 30)
        #expect(work.timeLabel == "09:00 – 17:00")
    }
}
