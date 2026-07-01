//
//  Components.swift
//  ZUBUN
//
//  Reusable UI building blocks. All honour Dynamic Type, ≥44pt targets, RTL
//  (leading/trailing), and reduced-motion where relevant.
//

import SwiftUI

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var tint: Color = Brand.orange
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.brandHeadline())
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.8 : 1)
    }
}

// MARK: - Card container

struct CardContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Tier badge

struct TierBadge: View {
    let tier: MemberTier
    var body: some View {
        Text(tier.label)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Brand.tierColor(tier).opacity(0.18), in: Capsule())
            .foregroundStyle(Brand.tierColor(tier))
    }
}

// MARK: - Inline banner (errors / config warnings)

struct InlineBanner: View {
    enum Kind { case error, warning, info }
    let kind: Kind
    let message: String

    private var color: Color {
        switch kind {
        case .error: return Brand.danger
        case .warning: return Brand.warning
        case .info: return Brand.stone500
        }
    }
    private var icon: String {
        switch kind {
        case .error: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(message).font(.subheadline).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Empty / loading states

struct LoadingState: View {
    var label: String = String(localized: "common.loading", defaultValue: "Loading…")
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundStyle(Brand.stone500)
            Text(title).font(.brandHeadline())
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - QR rendering (CoreImage)

import CoreImage.CIFilterBuiltins

enum QRImage {
    static func generate(from string: String, scale: CGFloat = 10) -> Image? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cg))
        #else
        return Image(decorative: cg, scale: 1)
        #endif
    }
}
