//
//  ResultOverlay.swift
//  ZUBUN
//
//  Tone-keyed overlay for scan results (spec §5.3): green stamped, amber
//  duplicate/limit/approval, reward celebratory, red errors. Offers "+ bonus".
//

import SwiftUI

struct ResultOverlay: View {
    let outcome: ScanOutcome
    var canBonus: Bool
    var onBonus: (Int) -> Void
    var onDismiss: () -> Void

    private var color: Color { Brand.toneColor(outcome.tone) }
    private var icon: String {
        switch outcome.tone {
        case .success: return "checkmark.circle.fill"
        case .reward:  return "gift.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 64))
                    .foregroundStyle(color)

                Text(outcome.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                if let progress = outcome.progress {
                    Text(progress)
                        .font(.brandMono())
                        .foregroundStyle(.secondary)
                }
                if let detail = outcome.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if canBonus {
                    HStack(spacing: 10) {
                        ForEach([1, 2, 3], id: \.self) { n in
                            Button("+\(n)") { onBonus(n); onDismiss() }
                                .font(.headline)
                                .frame(width: 56, height: 44)
                                .background(Brand.amber.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(Brand.ink)
                        }
                    }
                    Text("Add bonus stamps", comment: "Bonus hint")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Button(action: onDismiss) {
                    Text("Done", comment: "Dismiss overlay")
                        .font(.brandHeadline())
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(color, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(32)
        }
    }
}
