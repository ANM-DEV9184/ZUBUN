//
//  AdminBroadcastView.swift
//  ZUBUN
//
//  Admin → Announcements: push a ZUBUN-level message/offer to opted-in app users,
//  targeted by loyalty tier + activity. Estimate reach before sending. (6E)
//

import SwiftUI
import Observation

enum BroadcastActivity: String, CaseIterable, Identifiable {
    case any, active30, lapsed30
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return "Everyone"
        case .active30: return "Active (30d)"
        case .lapsed30: return "Lapsed (30d+)"
        }
    }
}

@MainActor
@Observable
final class AdminBroadcastViewModel {
    var title = ""
    var message = ""
    var link = ""
    var gold = false
    var silver = false
    var bronze = false
    var activity: BroadcastActivity = .any
    var reach: Int?
    var banner: (InlineBanner.Kind, String)?
    var busy = false
    private let service = AdminService()

    private var tiers: [String] {
        var t: [String] = []
        if gold { t.append("gold") }; if silver { t.append("silver") }; if bronze { t.append("bronze") }
        return t
    }
    private var activeWithin: Int? { activity == .active30 ? 30 : nil }
    private var lapsedBeyond: Int? { activity == .lapsed30 ? 30 : nil }
    var canSend: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !message.trimmingCharacters(in: .whitespaces).isEmpty && !busy
    }

    func estimate() async {
        busy = true; defer { busy = false }
        do {
            reach = try await service.broadcast(title: title, body: message, deepLink: link.isEmpty ? nil : link,
                                                tiers: tiers, activeWithin: activeWithin, lapsedBeyond: lapsedBeyond, dryRun: true)
        } catch { banner = (.error, "Couldn't estimate") }
    }

    func send() async {
        busy = true; defer { busy = false }
        do {
            let n = try await service.broadcast(title: title, body: message, deepLink: link.isEmpty ? nil : link,
                                                tiers: tiers, activeWithin: activeWithin, lapsedBeyond: lapsedBeyond, dryRun: false)
            banner = (.info, "Queued to \(n) member\(n == 1 ? "" : "s").")
            title = ""; message = ""; link = ""; reach = nil
        } catch let e as APIError { banner = (.error, e.errorDescription ?? "Send failed") }
        catch { banner = (.error, error.localizedDescription) }
    }
}

struct AdminBroadcastView: View {
    @State private var vm = AdminBroadcastViewModel()
    @State private var confirmSend = false

    var body: some View {
        Form {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            Section("Message") {
                TextField("Title", text: $vm.title)
                TextField("Message", text: $vm.message, axis: .vertical).lineLimit(2...5)
                TextField("Link (optional, https://…)", text: $vm.link)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            Section {
                Toggle("Gold tier", isOn: $vm.gold)
                Toggle("Silver tier", isOn: $vm.silver)
                Toggle("Bronze tier", isOn: $vm.bronze)
                Picker("Activity", selection: $vm.activity) {
                    ForEach(BroadcastActivity.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Audience")
            } footer: {
                Text("No tier selected = all tiers. Only members who opted in to ZUBUN announcements are reached.")
            }

            Section {
                Button {
                    Task { await vm.estimate() }
                } label: {
                    HStack { Text("Estimate reach"); Spacer(); if let r = vm.reach { Text("\(r)").foregroundStyle(Brand.orange) } }
                }
                .disabled(!vm.canSend)
                Button {
                    confirmSend = true
                } label: {
                    HStack { if vm.busy { ProgressView() }; Text("Send announcement").fontWeight(.semibold) }
                }
                .disabled(!vm.canSend)
            }
        }
        .navigationTitle(Text("Announcements", comment: "Admin broadcast title"))
        .zInlineTitle()
        .confirmationDialog("Send this announcement?", isPresented: $confirmSend, titleVisibility: .visible) {
            Button("Send now") { Task { await vm.send() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(vm.reach.map { "Reaches ~\($0) opted-in members." } ?? "Reaches all opted-in members matching your filters.")
        }
    }
}
