//
//  PlatformModifiers.swift
//  ZUBUN
//
//  Cross-platform shims for iOS-only SwiftUI modifiers so the multiplatform
//  target compiles everywhere. ZUBUN ships on iOS; on macOS these no-op.
//
//  Each function compiles exactly ONE branch per platform (via #if), so the
//  `some View` opaque type is unambiguous — no @ViewBuilder / _ConditionalContent.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum ZKeyboard {
    case number, phone, email
    #if os(iOS)
    var uiType: UIKeyboardType {
        switch self {
        case .number: return .numberPad
        case .phone:  return .phonePad
        case .email:  return .emailAddress
        }
    }
    #endif
}

extension View {
    /// Cross-platform keyboard type (no-op off iOS).
    func zKeyboard(_ type: ZKeyboard) -> some View {
        #if os(iOS)
        return self.keyboardType(type.uiType)
        #else
        return self
        #endif
    }

    /// Disable autocapitalization (no-op off iOS).
    func zNoAutocap() -> some View {
        #if os(iOS)
        return self.textInputAutocapitalization(.never)
        #else
        return self
        #endif
    }

    /// Inline navigation title (no-op off iOS).
    func zInlineTitle() -> some View {
        #if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }
}
