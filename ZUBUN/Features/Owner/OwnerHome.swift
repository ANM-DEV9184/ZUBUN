//
//  OwnerHome.swift
//  ZUBUN
//
//  Owner tab shell: Overview · Members · Approvals · More.
//

import SwiftUI

struct OwnerHome: View {
    @State private var context = OwnerContext.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack { OwnerDashboardView() }
                .tabItem { Label("Overview", systemImage: "chart.bar.xaxis") }
            NavigationStack { MembersView() }
                .tabItem { Label("Members", systemImage: "person.2.fill") }
            NavigationStack { ApprovalsView() }
                .tabItem { Label("Approvals", systemImage: "checklist") }
            NavigationStack { TeamView() }
                .tabItem { Label("Team", systemImage: "calendar") }
            NavigationStack { OwnerMoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(Brand.orange)
        .task {
            // Refresh the access token first so an expired JWT doesn't blank
            // every read, and any updated claims (merchant_id / role) apply.
            await OwnerService().refreshOwnerSession()
            await context.loadVenues()
            await PushManager.shared.onActiveSession()
        }
        // Returning from a long background → refresh the token so the first
        // action doesn't hit an expired JWT.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await OwnerService().refreshOwnerSession() } }
        }
    }
}

struct OwnerMoreView: View {
    @State private var showDelete = false
    @State private var banner: String?
    @State private var session = SessionStore.shared

    var body: some View {
        List {
            if session.isManager {
                Section { Label("Manager access", systemImage: "person.badge.shield.checkmark")
                    .font(.subheadline).foregroundStyle(.secondary) }
            }

            Section {
                NavigationLink { StaffManagementView() } label: { Label("Staff & join QR", systemImage: "person.2.badge.gearshape") }
                NavigationLink { StaffPerformanceView() } label: { Label("Staff performance", systemImage: "chart.bar.xaxis") }
                // Owner-only configuration.
                if !session.isManager {
                    NavigationLink { SettingsView() } label: { Label("Settings & venues", systemImage: "gearshape") }
                    NavigationLink { ManagersView() } label: { Label("Managers", systemImage: "person.2") }
                }
                NavigationLink { PayrollView() } label: { Label("Payroll", systemImage: "banknote") }
                NavigationLink { CampaignsView() } label: { Label("Campaigns", systemImage: "megaphone") }
                NavigationLink { FeedbackView() } label: { Label("Feedback", systemImage: "star.bubble") }
                NavigationLink { BillingView() } label: { Label("Billing", systemImage: "creditcard") }
                NavigationLink { SupportCenterView(auth: .owner) } label: { Label("Support", systemImage: "bubble.left.and.bubble.right") }
            }

            if let banner { Section { Text(banner).foregroundStyle(.secondary) } }

            Section {
                NavigationLink { OwnerChangePasswordView() } label: {
                    Label("Change password", systemImage: "key.fill")
                }
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await OwnerService().signOut()
                        OwnerContext.shared.reset()
                    }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            if !session.isManager {
                Section {
                    Button(role: .destructive) { showDelete = true } label: {
                        Label("Delete account", systemImage: "trash")
                    }
                } footer: {
                    Text("Sends a deletion request for your merchant account and data (UAE PDPL).",
                         comment: "Owner deletion footer")
                }
            }

            #if DEBUG
            DebugPushTokenRow()
            #endif
        }
        .navigationTitle(Text("More", comment: "Owner more title"))
        .confirmationDialog("Delete your account?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Request deletion", role: .destructive) {
                Task {
                    try? await OwnerService().createTicket(
                        subject: "Account deletion request",
                        category: "other",
                        body: "Please delete my ZUBUN merchant account and all associated data.")
                    banner = String(localized: "owner.delete.sent", defaultValue: "Deletion request sent. Our team will process it.")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This requests permanent deletion of your account and data. This can't be undone.")
        }
    }
}

/// Change the signed-in owner/manager password (managers start on a temp one).
struct OwnerChangePasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var banner: (InlineBanner.Kind, String)?
    @State private var saving = false

    private var valid: Bool { newPassword.count >= 8 && newPassword == confirm }

    var body: some View {
        Form {
            Section {
                SecureField("New password (min 8)", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm password", text: $confirm)
                    .textContentType(.newPassword)
            } footer: {
                Text("Use at least 8 characters.", comment: "Password rule")
            }

            if let banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            Section {
                Button {
                    Task {
                        saving = true; defer { saving = false }
                        do {
                            try await OwnerService().changePassword(new: newPassword)
                            banner = (.info, String(localized: "pw.changed", defaultValue: "Password updated."))
                            newPassword = ""; confirm = ""
                        } catch let e as APIError {
                            banner = (.error, e.errorDescription ?? "Couldn't update password")
                        } catch {
                            banner = (.error, error.localizedDescription)
                        }
                    }
                } label: {
                    HStack { if saving { ProgressView() }; Text("Update password") }
                }
                .disabled(!valid || saving)
            }
        }
        .navigationTitle(Text("Change password", comment: "Change password title"))
    }
}
