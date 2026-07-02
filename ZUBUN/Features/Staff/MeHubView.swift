//
//  MeHubView.swift
//  ZUBUN
//
//  Staff self-service hub (spec §5.6): today's status, achievements, change PIN,
//  account/device note, sign out.
//

import SwiftUI
import Observation

struct MeHubView: View {
    @State private var stats: ShiftStats?
    @State private var achievements: StaffAchievements?
    @State private var showChangePIN = false
    @State private var showRequests = false
    @State private var showDelete = false
    @Environment(\.openURL) private var openURL
    private let service = StaffService()
    private let session = SessionStore.shared

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44)).foregroundStyle(Brand.orange)
                    VStack(alignment: .leading) {
                        Text(session.staff?.displayName ?? "Staff").font(.brandHeadline())
                        if let rank = stats?.rank(forName: session.staff?.displayName) {
                            Text("Ranked #\(rank) today").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(String(localized: "me.stats", defaultValue: "My stats")) {
                LabeledContent("Stamps today", value: "\(stats?.today ?? 0)")
                LabeledContent("Last 7 days", value: "\(stats?.my7d ?? 0)")
            }

            if let a = achievements {
                Section(String(localized: "me.achievements", defaultValue: "Achievements")) {
                    LabeledContent("Lifetime stamps", value: "\(a.lifetime ?? 0)")
                    LabeledContent("This month", value: "\(a.month ?? 0)")
                    if let r = a.rank { LabeledContent("Venue rank", value: "#\(r)") }
                    if let s = a.streak, s > 0 { LabeledContent("On-time streak", value: "\(s) days") }
                    if let n = a.nextMilestone, n > 0 { LabeledContent("Next milestone", value: "\(n)") }
                }
            }

            Section {
                NavigationLink { AttendanceHistoryView() } label: {
                    Label("My attendance", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink { PayslipsView() } label: {
                    Label("My pay", systemImage: "banknote")
                }
                Button { showRequests = true } label: {
                    Label("Requests & leave", systemImage: "calendar.badge.clock")
                }
                Button { showChangePIN = true } label: {
                    Label("Change PIN", systemImage: "key.fill")
                }
                NavigationLink { SupportCenterView(auth: .staff) } label: {
                    Label("Help & support", systemImage: "bubble.left.and.bubble.right")
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await StaffService().logout(); session.clearStaff() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section {
                Button(role: .destructive) { showDelete = true } label: {
                    Label("Delete account", systemImage: "trash")
                }
            } footer: {
                Text("Staff accounts are managed by your venue owner. This sends a deletion request to support.",
                     comment: "Staff deletion footer")
            }

            #if DEBUG
            DebugPushTokenRow()
            #endif
        }
        .navigationTitle(Text("Me", comment: "Me tab title"))
        .task {
            async let s = service.shiftStats()
            async let a = service.achievements()
            stats = try? await s
            achievements = try? await a
        }
        .confirmationDialog("Request account deletion?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Email support", role: .destructive) {
                let venue = session.staff?.venueID ?? ""
                let subject = "Staff account deletion request"
                let body = "Please delete my ZUBUN staff account. Venue: \(venue)."
                var comps = URLComponents()
                comps.scheme = "mailto"
                comps.path = "support@zubun.io"
                comps.queryItems = [.init(name: "subject", value: subject), .init(name: "body", value: body)]
                if let url = comps.url { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This opens an email to request deletion of your staff account and data.")
        }
        .sheet(isPresented: $showChangePIN) { ChangePINSheet() }
        .sheet(isPresented: $showRequests) {
            NavigationStack { RequestsView() }
        }
    }
}

struct ChangePINSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var oldPin = ""
    @State private var newPin = ""
    @State private var banner: String?
    private let service = StaffService()

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Current PIN", text: $oldPin).zKeyboard(.number)
                SecureField("New PIN (4–8 digits)", text: $newPin).zKeyboard(.number)
                if let banner { Text(banner).foregroundStyle(Brand.orange) }
                Button("Update PIN") {
                    Task {
                        guard Validation.isValidPIN(newPin) else { banner = ResultCode.invalidPin.userMessage; return }
                        let res = try? await service.changePIN(old: oldPin, new: newPin)
                        banner = (res?.result ?? .invalid).userMessage
                        if res?.result == .ok { dismiss() }
                    }
                }
            }
            .navigationTitle(Text("Change PIN", comment: "Change PIN title"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
