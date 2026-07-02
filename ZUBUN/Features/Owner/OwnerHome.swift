//
//  OwnerHome.swift
//  ZUBUN
//
//  Owner tab shell: Overview · Members · Approvals · More.
//

import SwiftUI

struct OwnerHome: View {
    @State private var context = OwnerContext.shared

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
            await context.loadVenues()
            await PushManager.shared.onActiveSession()
        }
    }
}

struct OwnerMoreView: View {
    @State private var showDelete = false
    @State private var banner: String?

    var body: some View {
        List {
            Section {
                NavigationLink { StaffManagementView() } label: { Label("Staff & join QR", systemImage: "person.2.badge.gearshape") }
                NavigationLink { SettingsView() } label: { Label("Settings & venues", systemImage: "gearshape") }
                NavigationLink { PayrollView() } label: { Label("Payroll", systemImage: "banknote") }
                NavigationLink { CampaignsView() } label: { Label("Campaigns", systemImage: "megaphone") }
                NavigationLink { FeedbackView() } label: { Label("Feedback", systemImage: "star.bubble") }
                NavigationLink { BillingView() } label: { Label("Billing", systemImage: "creditcard") }
                NavigationLink { SupportView() } label: { Label("Support", systemImage: "bubble.left.and.bubble.right") }
            }

            if let banner { Section { Text(banner).foregroundStyle(.secondary) } }

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

            Section {
                Button(role: .destructive) { showDelete = true } label: {
                    Label("Delete account", systemImage: "trash")
                }
            } footer: {
                Text("Sends a deletion request for your merchant account and data (UAE PDPL).",
                     comment: "Owner deletion footer")
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
