//
//  SettingsView.swift
//  ZUBUN
//
//  Owner → Settings (spec C5/C14/C15): program rule, rewards catalog, promotions,
//  operations, branding, and venue lifecycle. All direct owner-JWT calls.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    // program
    var stamps = 8
    var dailyCap = 5
    var expiry = 60
    var grace = 0
    var rewardText = ""
    // operations
    var repeatApproval = 10
    var clockInterval = 30
    var staffBonus = false
    var birthdayGift = "none"
    var birthdayCount = 1
    var birthdayLabel = ""
    // branding
    var reviewURL = ""
    private var logoURL: String?
    // catalog
    var rewards: [RewardItem] = []
    var promotions: [Promotion] = []

    var banner: (InlineBanner.Kind, String)?
    var isLoading = false
    private var venueID: String?
    private let service = OwnerService()

    func load(venueID: String) async {
        self.venueID = venueID
        isLoading = true; defer { isLoading = false }
        if let rule = try? await service.programRule(venueID: venueID) {
            stamps = rule.stampsRequired ?? 8
            rewardText = rule.rewardText ?? ""
            dailyCap = rule.dailyCap ?? 5
            expiry = rule.expiryDays ?? 60
            grace = rule.graceDays ?? 0
        }
        if let cfg = try? await service.venueConfig(venueID: venueID) {
            repeatApproval = cfg.repeatStampApprovalMinutes ?? 10
            clockInterval = cfg.clockCodeIntervalMinutes ?? 30
            staffBonus = cfg.staffBonusEnabled ?? false
            birthdayGift = cfg.birthdayGift ?? "none"
            birthdayCount = cfg.birthdayGiftCount ?? 1
            birthdayLabel = cfg.birthdayGiftLabel ?? ""
            reviewURL = cfg.branding?.googleReviewUrl ?? ""
            logoURL = cfg.branding?.logoUrl
        }
        rewards = (try? await service.rewards(venueID: venueID)) ?? []
        promotions = (try? await service.promotions(venueID: venueID)) ?? []
    }

    private func run(_ label: String, _ work: () async throws -> Void) async {
        do { try await work(); banner = (.info, label) }
        catch let e as APIError { banner = (.error, e.errorDescription ?? "Error") }
        catch { banner = (.error, error.localizedDescription) }
    }

    func saveProgram() async {
        guard let v = venueID else { return }
        await run(String(localized: "settings.saved", defaultValue: "Saved")) {
            _ = try await service.updateProgramRule(venueID: v, stampsRequired: stamps, rewardText: rewardText,
                                                    dailyCap: dailyCap, expiryDays: expiry, graceDays: grace)
        }
    }

    func saveOperations() async {
        guard let v = venueID else { return }
        await run(String(localized: "settings.saved", defaultValue: "Saved")) {
            _ = try await service.setRepeatApproval(venueID: v, minutes: repeatApproval)
            _ = try await service.setClockInterval(venueID: v, minutes: clockInterval)
            _ = try await service.setStaffBonus(venueID: v, enabled: staffBonus)
            _ = try await service.setBirthdayGift(venueID: v, gift: birthdayGift, count: birthdayCount,
                                                  label: birthdayGift == "treat" ? birthdayLabel : nil)
        }
    }

    func saveBranding() async {
        guard let v = venueID else { return }
        await run(String(localized: "settings.saved", defaultValue: "Saved")) {
            _ = try await service.setBranding(venueID: v, branding: BrandingBlob(logoUrl: logoURL,
                                                                                 googleReviewUrl: reviewURL.isEmpty ? nil : reviewURL))
        }
    }

    func addReward(label: String, pointsCost: Int?) async {
        guard let v = venueID else { return }
        try? await service.addReward(venueID: v, label: label, pointsCost: pointsCost)
        rewards = (try? await service.rewards(venueID: v)) ?? rewards
    }
    func toggleReward(_ r: RewardItem) async {
        try? await service.setRewardActive(id: r.id, active: !(r.active ?? true))
        if let v = venueID { rewards = (try? await service.rewards(venueID: v)) ?? rewards }
    }
    func deleteReward(_ r: RewardItem) async {
        try? await service.deleteReward(id: r.id)
        rewards.removeAll { $0.id == r.id }
    }
    func addPromotion(label: String, multiplier: Int, recurrence: String, start: Date, end: Date, weekdays: [Int]) async {
        guard let v = venueID else { return }
        let iso = ISO8601DateFormatter()
        try? await service.addPromotion(venueID: v, label: label, multiplier: multiplier, recurrence: recurrence,
                                        startsAt: iso.string(from: start), endsAt: iso.string(from: end), weekdays: weekdays)
        promotions = (try? await service.promotions(venueID: v)) ?? promotions
    }
    func deletePromotion(_ p: Promotion) async {
        try? await service.deletePromotion(id: p.id)
        promotions.removeAll { $0.id == p.id }
    }
}

struct SettingsView: View {
    @State private var vm = SettingsViewModel()
    @State private var context = OwnerContext.shared
    @State private var showAddReward = false
    @State private var showAddPromo = false
    @State private var showCreateVenue = false

    var body: some View {
        Form {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            Section("Loyalty program") {
                Stepper("Stamps required: \(vm.stamps)", value: $vm.stamps, in: 1...100)
                TextField("Reward text", text: $vm.rewardText)
                Stepper("Daily cap: \(vm.dailyCap)", value: $vm.dailyCap, in: 1...20)
                Stepper("Expiry days: \(vm.expiry)", value: $vm.expiry, in: 0...365, step: 5)
                Stepper("Grace days: \(vm.grace)", value: $vm.grace, in: 0...60)
                Button("Save program") { Task { await vm.saveProgram() } }
            }

            Section("Operations") {
                Stepper("Repeat-stamp approval: \(vm.repeatApproval) min", value: $vm.repeatApproval, in: 0...240, step: 5)
                Stepper("Clock-in code changes every: \(vm.clockInterval) min", value: $vm.clockInterval, in: 15...120, step: 5)
                Toggle("Allow staff bonus stamps", isOn: $vm.staffBonus)
                Picker("Birthday gift", selection: $vm.birthdayGift) {
                    Text("None").tag("none"); Text("Bonus stamps").tag("stamps"); Text("Treat").tag("treat")
                }
                if vm.birthdayGift == "stamps" {
                    Stepper("Gift stamps: \(vm.birthdayCount)", value: $vm.birthdayCount, in: 1...5)
                } else if vm.birthdayGift == "treat" {
                    TextField("Treat label", text: $vm.birthdayLabel)
                }
                Button("Save operations") { Task { await vm.saveOperations() } }
            }

            Section("Branding") {
                TextField("Google review link (https://…)", text: $vm.reviewURL)
                    .zNoAutocap().autocorrectionDisabled()
                Button("Save branding") { Task { await vm.saveBranding() } }
            }

            Section("Rewards catalog") {
                ForEach(vm.rewards) { r in
                    HStack {
                        Text(r.label)
                        if let cost = r.pointsCost { Text("\(cost) pts").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Toggle("", isOn: Binding(get: { r.active ?? true }, set: { _ in Task { await vm.toggleReward(r) } }))
                            .labelsHidden()
                    }
                    .swipeActions { Button(role: .destructive) { Task { await vm.deleteReward(r) } } label: { Label("Delete", systemImage: "trash") } }
                }
                Button("Add reward") { showAddReward = true }
            }

            Section("Promotions") {
                ForEach(vm.promotions) { p in
                    HStack {
                        Text(p.label ?? "Promo")
                        Spacer()
                        Text("×\(p.multiplier ?? 2)").foregroundStyle(Brand.orange)
                        if p.recurrence == "weekly" { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
                    }
                    .swipeActions { Button(role: .destructive) { Task { await vm.deletePromotion(p) } } label: { Label("Delete", systemImage: "trash") } }
                }
                Button("Add promotion") { showAddPromo = true }
            }

            Section("Venues") {
                ForEach(context.venues) { v in
                    HStack {
                        Text(v.name)
                        Spacer()
                        if v.isPaused {
                            Button("Reactivate") { Task { await activate(v) } }.buttonStyle(.bordered)
                        } else {
                            Text("Active").font(.caption).foregroundStyle(Brand.success)
                            Button("Pause") { Task { await pause(v) } }.buttonStyle(.bordered).tint(Brand.warning)
                        }
                    }
                }
                Button("Add venue") { showCreateVenue = true }
            }
        }
        .navigationTitle(Text("Settings", comment: "Settings title"))
        .toolbar { VenueSwitcher(context: context) }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.load(venueID: v) }
        }
        .sheet(isPresented: $showAddReward) {
            AddRewardSheet { label, cost in Task { await vm.addReward(label: label, pointsCost: cost) } }
        }
        .sheet(isPresented: $showAddPromo) {
            AddPromotionSheet { label, mult, rec, start, end, days in
                Task { await vm.addPromotion(label: label, multiplier: mult, recurrence: rec, start: start, end: end, weekdays: days) }
            }
        }
        .sheet(isPresented: $showCreateVenue) {
            CreateVenueSheet { await reloadVenues() }
        }
    }

    private func pause(_ v: OwnerVenue) async { _ = try? await OwnerService().pauseVenue(venueID: v.id); await reloadVenues() }
    private func activate(_ v: OwnerVenue) async { _ = try? await OwnerService().activateVenue(venueID: v.id); await reloadVenues() }
    private func reloadVenues() async { context.reset(); await context.loadVenues() }
}

struct AddRewardSheet: View {
    var onSave: (String, Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var pointsCost = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Reward label", text: $label)
                TextField("Points cost (optional, points mode)", text: $pointsCost).zKeyboard(.number)
            }
            .navigationTitle(Text("Add reward", comment: "Add reward title"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onSave(label, Int(pointsCost)); dismiss() }.disabled(label.isEmpty)
                }
            }
        }
    }
}

struct AddPromotionSheet: View {
    var onSave: (String, Int, String, Date, Date, [Int]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var multiplier = 2
    @State private var recurrence = "once"
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(86_400)
    @State private var weekdays: Set<Int> = []

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $label)
                Stepper("Multiplier: ×\(multiplier)", value: $multiplier, in: 2...10)
                Picker("Recurrence", selection: $recurrence) {
                    Text("One-off").tag("once"); Text("Weekly").tag("weekly")
                }
                if recurrence == "once" {
                    DatePicker("Start", selection: $start)
                    DatePicker("End", selection: $end)
                } else {
                    HStack {
                        ForEach(0..<7, id: \.self) { d in
                            Button(dayNames[d]) {
                                if weekdays.contains(d) { weekdays.remove(d) } else { weekdays.insert(d) }
                            }
                            .font(.caption2)
                            .padding(6)
                            .background(weekdays.contains(d) ? Brand.orange : Brand.stone200, in: Capsule())
                            .foregroundStyle(weekdays.contains(d) ? .white : Brand.ink)
                        }
                    }
                }
            }
            .navigationTitle(Text("Add promotion", comment: "Add promo title"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let s = recurrence == "weekly" ? Date() : start
                        let e = recurrence == "weekly" ? Date().addingTimeInterval(5 * 365 * 86_400) : end
                        onSave(label, multiplier, recurrence, s, e, weekdays.sorted())
                        dismiss()
                    }.disabled(label.isEmpty || (recurrence == "weekly" && weekdays.isEmpty))
                }
            }
        }
    }
}

struct CreateVenueSheet: View {
    var onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var vertical = "cafe"
    @State private var stamps = 8
    @State private var rewardText = "Free coffee"
    @State private var dailyCap = 5
    @State private var banner: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Venue name", text: $name)
                Picker("Type", selection: $vertical) {
                    Text("Café").tag("cafe"); Text("Shisha").tag("shisha"); Text("Bar").tag("bar"); Text("Other").tag("other")
                }
                Stepper("Stamps: \(stamps)", value: $stamps, in: 1...100)
                TextField("Reward text", text: $rewardText)
                Stepper("Daily cap: \(dailyCap)", value: $dailyCap, in: 1...20)
                if let banner { Text(banner).foregroundStyle(Brand.danger) }
            }
            .navigationTitle(Text("Add venue", comment: "Create venue title"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            let res = try? await OwnerService().createVenue(name: name, vertical: vertical,
                                                                            stampsRequired: stamps, rewardText: rewardText, dailyCap: dailyCap)
                            if res?.result == "created" { await onCreated(); dismiss() }
                            else { banner = res?.result == "venue_limit_reached" ? "Venue limit reached for your plan." : "Couldn't create venue." }
                        }
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
