//
//  RootRouter.swift
//  ZUBUN
//
//  Decides the experience: resume a stored session, or pick a role and sign in.
//  A device can hold independent customer / staff / owner sessions (spec §3).
//

import SwiftUI

struct RootRouter: View {
    @State private var session = SessionStore.shared
    @State private var reachability = Reachability.shared
    @State private var selectedRole: AppRole?
    @State private var staffUnlocked = false

    var body: some View {
        Group {
            switch selectedRole {
            case .none:
                RoleChooserView(onSelect: { selectedRole = $0 })
            case .staff:
                if session.staff != nil {
                    if staffUnlocked || !BiometricGate.isAvailable {
                        StaffHome()
                    } else {
                        StaffLockView(
                            onUnlock: { staffUnlocked = true },
                            onSignOut: { session.clearStaff(); staffUnlocked = false })
                    }
                } else {
                    roleLogin { StaffLoginView(onAuthenticated: { staffUnlocked = true }) }
                }
            case .customer:
                if session.hasCustomerSession { CustomerHome() }
                else { roleLogin { CustomerLoginView { } } }
            case .owner:
                if session.hasOwnerSession {
                    if session.isAdmin { AdminHome() } else { OwnerHome() }
                } else { roleLogin { OwnerLoginView { } } }
            }
        }
        .overlay(alignment: .bottom) {
            if !reachability.isOnline {
                Label("You're offline", systemImage: "wifi.slash")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: reachability.isOnline)
        .onAppear(perform: resumeIfPossible)
        .onOpenURL(perform: handleURL)
    }

    /// A scanned/tapped `https://zubun.io/j/<venue>` universal link opens the app
    /// straight to the customer Join flow with the venue pre-filled.
    private func handleURL(_ url: URL) {
        switch QRParser.parse(url.absoluteString) {
        case let .joinVenue(venueID):
            CustomerRouter.shared.pendingJoinVenueID = venueID
            CustomerRouter.shared.tab = .join
            selectedRole = .customer
        case let .staffOnboard(token):
            // A tapped staff invite → open the app straight into staff onboarding.
            session.pendingStaffInvite = token
            selectedRole = .staff
        default:
            break
        }
    }

    /// Wraps a login screen with a "back to roles" affordance.
    private func roleLogin<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
            Button { selectedRole = nil } label: {
                Label("Roles", systemImage: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.leading, 16).padding(.top, 8)
        }
    }

    private func resumeIfPossible() {
        guard selectedRole == nil else { return }
        // Resume the most recent role that still has a live session.
        if let last = session.lastRole, hasSession(for: last) {
            selectedRole = last
        }
    }

    private func hasSession(for role: AppRole) -> Bool {
        switch role {
        case .staff: return session.staff != nil
        case .customer: return session.hasCustomerSession
        case .owner: return session.hasOwnerSession
        }
    }
}

/// Face ID / passcode lock shown when resuming a stored staff session.
struct StaffLockView: View {
    var onUnlock: () -> Void
    var onSignOut: () -> Void
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "faceid").font(.system(size: 56)).foregroundStyle(Brand.orange)
            Text("Locked", comment: "Lock screen title").font(.brandTitle())
            Text("Unlock to continue as \(SessionStore.shared.staff?.displayName ?? "staff").",
                 comment: "Lock screen subtitle")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if failed {
                InlineBanner(kind: .warning, message: String(localized: "lock.failed", defaultValue: "Couldn't verify. Try again."))
                    .padding(.horizontal)
            }
            PrimaryButton(title: String(localized: "lock.unlock", defaultValue: "Unlock"), systemImage: "lock.open") {
                Task { await attempt() }
            }
            .padding(.horizontal, 40)
            Button(role: .destructive) { onSignOut() } label: {
                Text("Sign out instead", comment: "Lock screen sign-out")
            }.font(.subheadline)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.stone.ignoresSafeArea())
        .task { await attempt() }
    }

    private func attempt() async {
        let ok = await BiometricGate.authenticate()
        if ok { onUnlock() } else { failed = true }
    }
}
