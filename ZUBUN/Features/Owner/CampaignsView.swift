//
//  CampaignsView.swift
//  ZUBUN
//
//  Owner → Campaigns (spec C12): compose + send venue-scoped in-app push
//  broadcasts (members get a notification that deep-links to that venue's card).
//  Owners start from a "recipe" (preset audience + suggested message they can
//  edit) or write a custom message to all members. Gated to Standard+ on an
//  active paid plan; `enqueue_campaign` also meters the monthly allowance.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class CampaignsViewModel {
    var plan: MerchantPlan?
    var campaigns: [CampaignRow] = []
    var banner: (InlineBanner.Kind, String)?
    var isLoading = false

    private var venueID: String?
    private let service = OwnerService()

    var canUse: Bool { plan?.canUseCampaigns ?? false }

    func load(venueID: String) async {
        self.venueID = venueID
        isLoading = true; defer { isLoading = false }
        plan = try? await service.merchantPlan()
        guard canUse else { return }
        campaigns = (try? await service.campaigns(venueID: venueID)) ?? []
    }

    func create(name: String, message: String, segment: CampaignSegmentDef) async {
        guard let v = venueID else { return }
        do {
            try await service.createCampaign(venueID: v, name: name, message: message, segment: segment)
            campaigns = (try? await service.campaigns(venueID: v)) ?? campaigns
            banner = (.info, String(localized: "campaign.created", defaultValue: "Draft created — tap Send when you're ready"))
        } catch let e as APIError { banner = (.error, e.errorDescription ?? "Error") }
        catch { banner = (.error, error.localizedDescription) }
    }

    func send(_ c: CampaignRow) async {
        guard let v = venueID else { return }
        let res = try? await service.sendCampaign(id: c.id)
        switch res?.result {
        case "enqueued":
            banner = (.info, String(localized: "campaign.sent", defaultValue: "Sending to \(res?.enqueued ?? 0) members"))
        case "over_limit":
            banner = (.warning, String(localized: "campaign.over", defaultValue: "You've used all your sends for this month"))
        case "no_content":
            banner = (.warning, String(localized: "campaign.nocontent", defaultValue: "Add a message before sending"))
        case "venue_paused":
            banner = (.warning, ResultCode.programPaused.userMessage)
        default:
            banner = (.warning, res?.result ?? "Couldn't send")
        }
        plan = try? await service.merchantPlan()
        campaigns = (try? await service.campaigns(venueID: v)) ?? campaigns
    }
}

struct CampaignsView: View {
    @State private var vm = CampaignsViewModel()
    @State private var context = OwnerContext.shared
    @State private var showCompose = false

    var body: some View {
        Group {
            if vm.isLoading && vm.plan == nil {
                LoadingState()
            } else if !vm.canUse {
                EmptyStateView(systemImage: "lock.fill",
                               title: String(localized: "campaign.locked", defaultValue: "Campaigns need Standard+"),
                               message: String(localized: "campaign.locked.detail", defaultValue: "Upgrade to an active Standard or Multi plan to send push broadcasts to your members."))
            } else {
                List {
                    if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }
                    if let plan = vm.plan {
                        Section {
                            HStack {
                                Label(String(localized: "campaign.channel", defaultValue: "In-app push"), systemImage: "bell.badge.fill")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(plan.campaignsRemaining) / \(plan.campaignAllowance) sends left")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(plan.campaignsRemaining == 0 ? Brand.warning : Brand.orange)
                            }
                        } footer: {
                            Text("Each member you reach uses one send. Free in-app notification that opens this venue's card. Resets on the 1st of each month.",
                                 comment: "Campaign channel footer")
                        }
                    }
                    ForEach(vm.campaigns) { c in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.name ?? "Untitled").font(.headline)
                                Text("\(c.audienceLabel) · \((c.status ?? "").capitalized)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if c.status == "draft" {
                                Button("Send") { Task { await vm.send(c) } }
                                    .buttonStyle(.borderedProminent).tint(Brand.orange)
                            }
                        }
                    }
                    if vm.campaigns.isEmpty {
                        Text("No campaigns yet. Tap + to create one.").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(Text("Campaigns", comment: "Campaigns title"))
        .toolbar {
            VenueSwitcher(context: context)
            if vm.canUse {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCompose = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.load(venueID: v) }
        }
        .sheet(isPresented: $showCompose) {
            ComposeCampaignSheet(venueName: context.selectedVenue?.name ?? "your venue") { name, message, segment in
                Task { await vm.create(name: name, message: message, segment: segment) }
            }
        }
    }
}

struct ComposeCampaignSheet: View {
    let venueName: String
    var onCreate: (String, String, CampaignSegmentDef) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var recipe = CampaignRecipe.all[0]
    @State private var name = ""
    @State private var message = ""
    @State private var days = 30

    /// The final audience — recipe's segment, with the win-back day count applied.
    private var segment: CampaignSegmentDef {
        var s = recipe.segment
        if s.daysInactive != nil { s.daysInactive = days }
        return s
    }

    /// Live preview: the member sees the venue name in place of {{1}}.
    private var previewBody: String {
        message.replacingOccurrences(of: "{{1}}", with: venueName)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !message.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $recipe) {
                        ForEach(CampaignRecipe.all) { r in
                            Label(r.title, systemImage: r.icon).tag(r)
                        }
                    } label: {
                        Text("Campaign type", comment: "Recipe picker label")
                    }
                    .onChange(of: recipe) { _, r in apply(r) }
                } footer: {
                    Text("Pick a ready-made campaign or start with a custom message. You can edit everything below.",
                         comment: "Recipe footer")
                }

                Section(String(localized: "campaign.name.section", defaultValue: "Name")) {
                    TextField("Campaign name (only you see this)", text: $name)
                }

                Section {
                    Label(segment.label, systemImage: "person.2.fill")
                        .font(.subheadline)
                    if recipe.segment.daysInactive != nil {
                        Stepper("Not seen in \(days)+ days", value: $days, in: 7...120, step: 7)
                    }
                } header: {
                    Text("Who it goes to", comment: "Audience section")
                } footer: {
                    Text(audienceHelp)
                }

                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 90)
                        .accessibilityLabel(Text("Message text", comment: "Message editor a11y"))
                } header: {
                    Text("Message", comment: "Message section")
                } footer: {
                    Text("Tip: type {{1}} anywhere to insert your venue's name.",
                         comment: "Message placeholder help")
                }

                // Live preview of the push the member will receive.
                Section(String(localized: "campaign.preview", defaultValue: "Preview")) {
                    NotificationPreview(title: venueName, message: previewBody)
                }
            }
            .navigationTitle(Text("New campaign", comment: "Compose title"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate(name, message, segment); dismiss() }
                        .disabled(!canCreate)
                }
            }
            .onAppear { apply(recipe) }
        }
    }

    private func apply(_ r: CampaignRecipe) {
        message = r.message
        if name.isEmpty || CampaignRecipe.all.contains(where: { $0.title == name }) {
            name = r.title
        }
    }

    private var audienceHelp: String {
        let s = recipe.segment
        if s.newWithin != nil { return "Members who joined recently — a warm welcome." }
        if s.goldOnly == true { return "Only your Gold-tier members — your very top guests (30+ lifetime stamps)." }
        if s.champion == true { return "Your loyal members — Silver & Gold tier, earned automatically from lifetime visits (10+ / 30+ stamps)." }
        if s.atRisk == true { return "Members whose last visit was 2–4 weeks ago — nudge them before they drift." }
        if s.birthdayToday == true { return "Members whose birthday is today." }
        if s.birthdayWithin != nil { return "Members with a birthday in the next few days — greet them ahead of the day." }
        if s.stampsToReward != nil { return "Members who are 1–2 stamps away from a free reward." }
        if s.rewardUnredeemed == true { return "Members holding a reward they haven't claimed yet." }
        if s.daysInactive != nil { return "Members who haven't visited for a while — win them back." }
        return "Everyone with an active card who opted in to messages."
    }
}

/// A small mock of the iOS notification banner so owners see exactly what lands.
struct NotificationPreview: View {
    let title: String
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Brand.orange)
                .frame(width: 34, height: 34)
                .overlay(Image(systemName: "bell.fill").font(.footnote).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Your venue" : title)
                    .font(.subheadline.weight(.semibold))
                Text(message.isEmpty ? "Your message will appear here." : message)
                    .font(.subheadline)
                    .foregroundStyle(message.isEmpty ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.stone))
    }
}
