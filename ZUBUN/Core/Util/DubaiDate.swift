//
//  DubaiDate.swift
//  ZUBUN
//
//  UAE-only: all day boundaries / display use Asia/Dubai (fixed +04:00).
//

import Foundation

enum DubaiDate {
    static let timeZone = TimeZone(identifier: AppConfig.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 4 * 3600)!

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    /// e.g. "Mon, 18 Jun"
    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale.current
        f.dateFormat = "EEE, d MMM"
        return f.string(from: date)
    }

    /// e.g. "14:35"
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale.current
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    // MARK: - Rota date helpers (yyyy-MM-dd in Dubai time)

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func ymdString(_ date: Date) -> String { ymd.string(from: date) }
    static func date(fromYMD string: String) -> Date? { ymd.date(from: string) }

    static func addDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func addDays(_ days: Int, toDateString string: String) -> String? {
        guard let d = date(fromYMD: string) else { return nil }
        return ymdString(addDays(days, to: d))
    }

    /// Monday of the week containing `date` (Dubai).
    static func weekStart(_ date: Date) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? date
    }

    static func todayString() -> String { ymdString(Date()) }

    /// "yyyy-MM" for the given date (Dubai).
    static func monthString(_ date: Date) -> String { String(ymdString(date).prefix(7)) }

    /// The current month + the previous `n-1` months as "yyyy-MM", newest first.
    static func recentMonths(_ n: Int) -> [String] {
        (0..<n).compactMap { i in
            calendar.date(byAdding: .month, value: -i, to: Date()).map(monthString)
        }
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func hmString(_ date: Date) -> String { hm.string(from: date) }

    /// Combine a day (from a date picker) + a time (from a time picker), both in
    /// Dubai local terms, into a UTC ISO8601 timestamp string.
    static func combineISO(day: Date, time: Date) -> String {
        let cal = calendar
        let d = cal.dateComponents([.year, .month, .day], from: day)
        let t = cal.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = d.year; merged.month = d.month; merged.day = d.day
        merged.hour = t.hour; merged.minute = t.minute
        merged.timeZone = timeZone
        let date = cal.date(from: merged) ?? day
        return ISO8601DateFormatter().string(from: date)
    }
    static func date(fromHM string: String) -> Date? {
        hm.date(from: ShiftCell.trimSeconds(string) ?? string)
    }

    /// e.g. "Mon 30" for a compact week strip.
    static func weekdayShort(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale.current
        f.dateFormat = "EEE d"
        return f.string(from: date)
    }

    /// ISO8601 parser tolerant of fractional seconds.
    static func parseISO(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
