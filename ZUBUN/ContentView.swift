//
//  ContentView.swift
//  ZUBUN
//
//  The role chooser — the cold-start screen when no session is being resumed.
//

import SwiftUI

struct RoleChooserView: View {
    var onSelect: (AppRole) -> Void
    @State private var session = SessionStore.shared

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 52)).foregroundStyle(Brand.orange)
                Text("ZUBUN").font(.system(size: 40, weight: .heavy, design: .rounded))
                Text("Loyalty & attendance", comment: "App tagline")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                ForEach(AppRole.allCases) { role in
                    Button { onSelect(role) } label: {
                        RoleCard(role: role, hasSession: hasSession(for: role))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
            if !AppConfig.isAnonKeyConfigured {
                InlineBanner(kind: .warning,
                             message: String(localized: "config.anon_missing",
                                             defaultValue: "App not fully configured: Supabase anon key is missing."))
                    .padding(.horizontal, 20)
            }
            Text("UAE · AED · EN / العربية", comment: "Locale footer")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.stone.ignoresSafeArea())
    }

    private func hasSession(for role: AppRole) -> Bool {
        switch role {
        case .staff: return session.staff != nil
        case .customer: return session.hasCustomerSession
        case .owner: return session.hasOwnerSession
        }
    }
}

struct RoleCard: View {
    let role: AppRole
    let hasSession: Bool
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: role.systemImage)
                .font(.title2).frame(width: 44, height: 44)
                .background(Brand.amber.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Brand.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(role.title).font(.brandHeadline()).foregroundStyle(Brand.ink)
                Text(hasSession ? String(localized: "role.resume", defaultValue: "Tap to resume") : role.subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
