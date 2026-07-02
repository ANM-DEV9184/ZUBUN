//
//  AdminMerchantsView.swift
//  ZUBUN
//
//  Admin → Merchants: directory + per-merchant control (plan, billing, suspend).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AdminMerchantsViewModel {
    var merchants: [AdminMerchant] = []
    var query = ""
    var isLoading = false
    private let service = AdminService()

    func load() async {
        isLoading = true; defer { isLoading = false }
        merchants = (try? await service.merchants(q: query)) ?? []
    }
}

struct AdminMerchantsView: View {
    @State private var vm = AdminMerchantsViewModel()

    var body: some View {
        List {
            if vm.merchants.isEmpty && !vm.isLoading {
                Text("No merchants found.").foregroundStyle(.secondary)
            }
            ForEach(vm.merchants) { m in
                NavigationLink { AdminMerchantDetailView(merchantID: m.id) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.name ?? "—").font(.headline)
                        HStack(spacing: 6) {
                            Text((m.planTier ?? "starter").capitalized)
                            Text("·").foregroundStyle(.secondary)
                            Text(m.billingStatus ?? "—")
                            Text("· \(m.venueCount ?? 0) venue\((m.venueCount ?? 0) == 1 ? "" : "s")").foregroundStyle(.secondary)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(Text("Merchants", comment: "Admin merchants title"))
        .searchable(text: $vm.query, prompt: Text("Search merchants"))
        .onSubmit(of: .search) { Task { await vm.load() } }
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }
}

@MainActor
@Observable
final class AdminMerchantDetailViewModel {
    var detail: AdminMerchantDetail?
    var banner: (InlineBanner.Kind, String)?
    var saving = false
    let merchantID: String
    private let service = AdminService()
    init(merchantID: String) { self.merchantID = merchantID }

    func load() async { detail = try? await service.merchant(id: merchantID) }

    func update(plan: String?, billing: String?) async {
        saving = true; defer { saving = false }
        do {
            try await service.updateMerchant(id: merchantID, planTier: plan, billingStatus: billing)
            banner = (.info, "Saved."); await load()
        } catch let e as APIError { banner = (.error, e.errorDescription ?? "Failed") }
        catch { banner = (.error, error.localizedDescription) }
    }

    func account(_ action: String) async {
        do {
            try await service.account(id: merchantID, action: action)
            banner = (.info, action == "disable" ? "Owner login disabled." : "Owner login re-enabled.")
        } catch let e as APIError { banner = (.error, e.errorDescription ?? "Failed") }
        catch { banner = (.error, error.localizedDescription) }
    }
}

struct AdminMerchantDetailView: View {
    @State private var vm: AdminMerchantDetailViewModel
    @State private var plan: AdminPlanTier = .starter
    @State private var billing: AdminBilling = .active
    @State private var confirmDisable = false

    init(merchantID: String) { _vm = State(initialValue: AdminMerchantDetailViewModel(merchantID: merchantID)) }

    var body: some View {
        Form {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            if let m = vm.detail?.merchant {
                Section {
                    LabeledContent("Merchant", value: m.name ?? "—")
                    if let c = m.ownerContact { LabeledContent("Owner", value: c) }
                    LabeledContent("Members", value: "\(vm.detail?.members ?? 0)")
                } header: { Text("Overview") }

                Section {
                    Picker("Plan", selection: $plan) {
                        ForEach(AdminPlanTier.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Billing", selection: $billing) {
                        ForEach(AdminBilling.allCases) { Text($0.label).tag($0) }
                    }
                    Button {
                        Task { await vm.update(plan: plan.rawValue, billing: billing.rawValue) }
                    } label: {
                        HStack { if vm.saving { ProgressView() }; Text("Save changes") }
                    }
                    .disabled(vm.saving)
                } header: { Text("Plan & billing") }

                Section {
                    ForEach(vm.detail?.venues ?? []) { v in
                        HStack {
                            Text(v.name ?? "—")
                            Spacer()
                            Text(v.status ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Venues") }

                Section {
                    Button(role: .destructive) { confirmDisable = true } label: {
                        Label("Disable owner login", systemImage: "person.crop.circle.badge.xmark")
                    }
                    Button { Task { await vm.account("enable") } } label: {
                        Label("Re-enable owner login", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } header: { Text("Account") } footer: {
                    Text("Disabling blocks the owner from signing in. Members' data and rewards are untouched.")
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(vm.detail?.merchant.name ?? "Merchant"))
        .zInlineTitle()
        .confirmationDialog("Disable this owner's login?", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("Disable login", role: .destructive) { Task { await vm.account("disable") } }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await vm.load()
            if let m = vm.detail?.merchant {
                plan = AdminPlanTier(rawValue: m.planTier ?? "starter") ?? .starter
                billing = AdminBilling(rawValue: m.billingStatus ?? "active") ?? .active
            }
        }
    }
}
