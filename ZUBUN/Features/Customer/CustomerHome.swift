//
//  CustomerHome.swift
//  ZUBUN
//
//  Customer tab shell: Cards · Join · Settings. Settings carries the mandatory
//  in-app account deletion (Apple §6).
//

import SwiftUI

struct CustomerHome: View {
    @State private var router = CustomerRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.cardPath) { MyCardsView() }
                .tabItem { Label("Cards", systemImage: "wallet.pass.fill") }
                .tag(CustomerTab.cards)
            NavigationStack { JoinVenueView() }
                .tabItem { Label("Join", systemImage: "plus.circle.fill") }
                .tag(CustomerTab.join)
            NavigationStack { NotificationsView() }
                .tabItem { Label("Inbox", systemImage: "bell.fill") }
                .badge(router.unread)
                .tag(CustomerTab.inbox)
            NavigationStack { CustomerSettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(CustomerTab.settings)
        }
        .tint(Brand.orange)
        .task {
            // Refresh the access token first so an expired JWT doesn't blank the wallet.
            await CustomerService().refreshCustomerSession()
            await PushManager.shared.onActiveSession()
            await router.refreshUnread()
        }
    }
}

struct CustomerSettingsView: View {
    @State private var showDeleteConfirm = false
    @State private var banner: String?
    private let service = CustomerService()
    private let session = SessionStore.shared

    var body: some View {
        List {
            Section(String(localized: "settings.privacy", defaultValue: "Privacy")) {
                Button {
                    Task {
                        let res = try? await service.optOut(membershipID: nil)
                        banner = (res?.result ?? .ok).userMessage
                    }
                } label: { Label("Opt out of marketing", systemImage: "bell.slash") }
            }

            Section {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete my account", systemImage: "trash")
                }
            } footer: {
                Text("Deletes your data under UAE PDPL after a 30-day grace period.",
                     comment: "Account deletion footer")
            }

            Section {
                Button { Task { await service.signOut() } } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            if let banner { Section { Text(banner).foregroundStyle(.secondary) } }

            #if DEBUG
            DebugPushTokenRow()
            Section("Debug") {
                Button {
                    Task {
                        do {
                            let res = try await service.sendTestPush()
                            banner = res.summary
                        } catch let e as APIError {
                            banner = e.errorDescription ?? "Test push failed"
                        } catch {
                            banner = error.localizedDescription
                        }
                    }
                } label: { Label("Send test push", systemImage: "paperplane") }
            }
            #endif
        }
        .navigationTitle(Text("Settings", comment: "Customer settings title"))
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task {
                    let res = try? await service.deleteAccount()
                    banner = (res?.result ?? .ok).userMessage
                    await service.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This requests erasure of your loyalty data. This can't be undone.")
        }
    }
}
