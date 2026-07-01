//
//  Theme.swift
//  ZUBUN
//
//  Brand palette + typography. Light, warm (amber/stone) for hubs & wallet;
//  dark immersive for the staff scanner. (Spec §3 / §4.)
//

import SwiftUI

enum Brand {
    static let amber  = Color(hex: 0xF4B942)
    static let orange = Color(hex: 0xE8651A)
    static let ink    = Color(hex: 0x1C1917)
    static let stone  = Color(hex: 0xF5F5F4)
    static let stone200 = Color(hex: 0xE7E5E4)
    static let stone500 = Color(hex: 0x78716C)

    static let success = Color(hex: 0x16A34A)
    static let warning = Color(hex: 0xD97706)
    static let danger  = Color(hex: 0xDC2626)

    /// Tier accents.
    static func tierColor(_ tier: MemberTier) -> Color {
        switch tier {
        case .bronze: return Color(hex: 0xB45309)
        case .silver: return Color(hex: 0x94A3B8)
        case .gold:   return amber
        }
    }

    static func toneColor(_ tone: ResultTone) -> Color {
        switch tone {
        case .success: return success
        case .reward:  return orange
        case .warning: return warning
        case .error:   return danger
        case .info:    return stone500
        }
    }
}

extension Color {
    /// Adaptive card surface (cross-platform).
    static var card: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color.white
        #endif
    }

    /// Adaptive sheet/background surface (cross-platform).
    static var surface: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color.white
        #endif
    }

    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Font {
    static func brandTitle() -> Font { .system(.largeTitle, design: .rounded).weight(.bold) }
    static func brandHeadline() -> Font { .system(.headline, design: .rounded).weight(.semibold) }
    static func brandMono() -> Font { .system(.title2, design: .monospaced).weight(.bold) }
}
