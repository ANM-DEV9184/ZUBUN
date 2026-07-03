//
//  QRParsing.swift
//  ZUBUN
//
//  The scanner only ever DECODES + relays tokens; it never mints them.
//  Formats (spec §8):
//    customer/identity QR : dayem:c:<base64url payload>.<hmac>   (24h rotating, venue-scoped)
//    reward QR            : dayem:r:<rawToken>                    (single-use)
//    venue join link      : .../j/<venueId>
//

import Foundation

enum ScannedCode: Equatable {
    /// The full `dayem:c:…` string to relay to /api/staff/stamp.
    case customer(qr: String)
    /// The full `dayem:r:…` string to relay to /api/staff/redeem.
    case reward(qr: String)
    /// A venue id extracted from a /j/<venueId> join link or raw UUID.
    case joinVenue(venueID: String)
    /// A staff onboarding token from a /staff/onboard/<token> invite link.
    case staffOnboard(token: String)
    case unknown(raw: String)
}

enum QRParser {
    static func parse(_ raw: String) -> ScannedCode {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("dayem:c:") {
            return .customer(qr: value)
        }
        if value.hasPrefix("dayem:r:") {
            return .reward(qr: value)
        }

        // Staff onboarding links such as https://zubun.io/staff/onboard/<token>
        if let range = value.range(of: "/staff/onboard/") {
            let tail = value[range.upperBound...]
            let tok = tail.split(separator: "/").first.map(String.init) ?? String(tail)
            let clean = tok.split(separator: "?").first.map(String.init) ?? tok
            if !clean.isEmpty { return .staffOnboard(token: clean) }
        }

        // Join links such as https://zubun.io/j/<uuid>
        if let range = value.range(of: "/j/") {
            let tail = value[range.upperBound...]
            let id = tail.split(separator: "/").first.map(String.init) ?? String(tail)
            let clean = id.split(separator: "?").first.map(String.init) ?? id
            if isUUID(clean) { return .joinVenue(venueID: clean) }
        }

        if isUUID(value) { return .joinVenue(venueID: value) }

        return .unknown(raw: value)
    }

    static func isUUID(_ s: String) -> Bool {
        UUID(uuidString: s) != nil
    }
}
