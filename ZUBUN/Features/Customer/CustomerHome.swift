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
    @State private var bMonth = 1
    @State private var bDay = 1
    @State private var savingBirthday = false
    private let service = CustomerService()
    private let session = SessionStore.shared

    var body: some View {
        List {
            Section {
                Picker(String(localized: "settings.bday.month", defaultValue: "Month"), selection: $bMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(Calendar.current.monthSymbols[m - 1]).tag(m)
                    }
                }
                Picker(String(localized: "settings.bday.day", defaultValue: "Day"), selection: $bDay) {
                    ForEach(1...31, id: \.self) { d in Text("\(d)").tag(d) }
                }
                Button {
                    Task {
                        savingBirthday = true; defer { savingBirthday = false }
                        do {
                            _ = try await service.setBirthday(month: bMonth, day: bDay)
                            banner = String(localized: "settings.bday.saved", defaultValue: "Birthday saved 🎂")
                        } catch let e as APIError {
                            banner = e.errorDescription ?? "Couldn't save birthday"
                        } catch { banner = error.localizedDescription }
                    }
                } label: {
                    HStack { if savingBirthday { ProgressView() }; Text("Save birthday") }
                }
                .disabled(savingBirthday)
            } header: {
                Text("My birthday", comment: "Customer birthday section")
            } footer: {
                Text("Add your birthday so your favourite venues can surprise you. We only keep the day and month — never the year.",
                     comment: "Customer birthday footer")
            }

            Section {
                NavigationLink { SupportCenterView(auth: .customer) } label: {
                    Label("Help & support", systemImage: "bubble.left.and.bubble.right")
                }
            }

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
