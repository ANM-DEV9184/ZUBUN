//
//  CampaignsView.swift
//  ZUBUN
//
//  Owner → Campaigns (spec C12): compose + send venue-scoped in-app push
//  broadcasts (members get a notification that deep-links to that venue's card).
//  Gated to Standard+ on an active paid plan (enforced client-side;
//  `enqueue_campaign` also meters the monthly campaign allowance server-side).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class CampaignsViewModel {
    var plan: MerchantPlan?
    var campaigns: [CampaignRow] = []
    var templates: [TemplateRow] = []
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
        templates = (try? await service.marketingTemplates()) ?? []
        campaigns = (try? await service.campaigns(venueID: venueID)) ?? []
    }

    func create(name: String, templateID: String, segment: String, days: Int) async {
        guard let v = venueID else { return }
        do {
            try await service.createCampaign(venueID: v, name: name, templateID: templateID, segment: segment, daysInactive: days)
            campaigns = (try? await service.campaigns(venueID: v)) ?? campaigns
            banner = (.info, String(localized: "campaign.created", defaultValue: "Draft created"))
        } catch let e as APIError { banner = (.error, e.errorDescription ?? "Error") }
        catch { banner = (.error, error.localizedDescription) }
    }

    func send(_ c: CampaignRow) async {
        guard let v = venueID else { return }
        let res = try? await service.sendCampaign(id: c.id)
        switch res?.result {
        case "enqueued": banner = (.info, String(localized: "campaign.sent", defaultValue: "Sending to \(res?.enqueued ?? 0) members"))
        case "over_limit": banner = (.warning, String(localized: "campaign.over", defaultValue: "Monthly campaign allowance reached"))
        case "venue_paused": banner = (.warning, ResultCode.programPaused.userMessage)
        default: banner = (.warning, res?.result ?? "Couldn't send")
        }
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
                                Text("\(plan.campaignsRemaining) / \(plan.campaignAllowance) left")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(plan.campaignsRemaining == 0 ? Brand.warning : Brand.orange)
                            }
                        } footer: {
                            Text("Members get a notification that opens this venue's card. Resets monthly.",
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
                                Button("Send") { Task { await vm.send(c) } }.buttonStyle(.borderedProminent).tint(Brand.orange)
                            }
                        }
                    }
                    if vm.campaigns.isEmpty {
                        Text("No campaigns yet.").foregroundStyle(.secondary)
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
                        .disabled(vm.templates.isEmpty)
                }
            }
        }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.load(venueID: v) }
        }
        .sheet(isPresented: $showCompose) {
            ComposeCampaignSheet(templates: vm.templates) { name, tid, seg, days in
                Task { await vm.create(name: name, templateID: tid, segment: seg, days: days) }
            }
        }
    }
}

struct ComposeCampaignSheet: View {
    let templates: [TemplateRow]
    var onCreate: (String, String, String, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var templateID = ""
    @State private var segment = "all"
    @State private var days = 14

    var body: some View {
        NavigationStack {
            Form {
                TextField("Campaign name", text: $name)
                Picker("Template", selection: $templateID) {
                    Text("Select…").tag("")
                    ForEach(templates) { t in
                        Text("\(t.name ?? "template") (\(t.language ?? "en"))").tag(t.id)
                    }
                }
                Picker("Audience", selection: $segment) {
                    Text("All members").tag("all")
                    Text("Lapsed").tag("lapsed")
                }
                if segment == "lapsed" {
                    Stepper("Inactive for \(days)+ days", value: $days, in: 7...120, step: 7)
                }
            }
            .navigationTitle(Text("New campaign", comment: "Compose title"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate(name, templateID, segment, days); dismiss() }
                        .disabled(name.isEmpty || templateID.isEmpty)
                }
            }
        }
    }
}
