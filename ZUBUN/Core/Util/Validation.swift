//
//  Validation.swift
//  ZUBUN
//
//  Small input validators shared across roles.
//

import Foundation

enum Validation {
    /// E.164: a leading + and 7–15 digits, first digit non-zero. Matches the backend regex.
    static func isValidE164(_ phone: String) -> Bool {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: #"^\+[1-9]\d{6,14}$"#, options: .regularExpression) != nil
    }

    /// Staff PINs are 4–8 digits.
    static func isValidPIN(_ pin: String) -> Bool {
        pin.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
    }

    /// Normalises a UAE-typed number towards E.164 (best effort, non-destructive).
    /// Leaves an already-+ number untouched; maps a leading 0 to +971.
    static func normalizeUAEPhone(_ input: String) -> String {
        var s = input.filter { $0 == "+" || $0.isNumber }
        if s.hasPrefix("+") { return s }
        if s.hasPrefix("00") { return "+" + s.dropFirst(2) }
        if s.hasPrefix("0") { s = String(s.dropFirst()) }
        if s.hasPrefix("971") { return "+" + s }
        return "+971" + s
    }
}
