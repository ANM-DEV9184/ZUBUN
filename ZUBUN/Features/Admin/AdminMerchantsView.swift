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

    var shareLink: String?   // reset-password / impersonate URL to copy

    func account(_ action: String, email: String? = nil) async {
        do {
            let url = try await service.account(id: merchantID, action: action, email: email)
            if let url { shareLink = url }
            banner = (.info, message(for: action))
            if action == "offboard" { await load() }
        } catch let e as APIError { banner = (.error, e.errorDescription ?? "Failed") }
        catch { banner = (.error, error.localizedDescription) }
    }

    func impersonate() async {
        do { shareLink = try await service.impersonate(id: merchantID); banner = (.info, "Owner sign-in link ready — copy & open in a browser.") }
        catch { banner = (.error, "Couldn't create link") }
    }

    func staffAction(_ action: String, staffID: String) async {
        do {
            try await service.venueAction(action: action, staffId: staffID)
            banner = (.info, "Done."); await load()
        } catch { banner = (.error, "Action failed") }
    }

    private func message(for action: String) -> String {
        switch action {
        case "disable": return "Owner login disabled."
        case "enable": return "Owner login re-enabled."
        case "offboard": return "Owner offboarded (plan cancelled)."
        case "reset_password": return "Password-reset link ready — copy it below."
        case "change_email": return "Owner email updated."
        default: return "Done."
        }
    }
}

struct AdminMerchantDetailView: View {
    @State private var vm: AdminMerchantDetailViewModel
    @State private var plan: AdminPlanTier = .starter
    @State private var billing: AdminBilling = .active
    @State private var confirmDisable = false
    @State private var confirmOffboard = false
    @State private var showEmailPrompt = false
    @State private var newEmail = ""

    init(merchantID: String) { _vm = State(initialValue: AdminMerchantDetailViewModel(merchantID: merchantID)) }

    var body: some View {
        Form {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            if let link = vm.shareLink {
                Section {
                    Text(link).font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
                    if let url = URL(string: link) {
                        ShareLink(item: url) { Label("Share / open link", systemImage: "square.and.arrow.up") }
                    }
                } header: { Text("One-time link") } footer: {
                    Text("Open in a browser. Single-use and time-limited.")
                }
            }

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

                if let staff = vm.detail?.staff, !staff.isEmpty {
                    Section {
                        ForEach(staff) { s in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.displayName ?? "Staff")
                                    Text(s.status ?? "").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button("Reset device") { Task { await vm.staffAction("reset_device", staffID: s.id) } }
                                    if s.isActive {
                                        Button("Suspend", role: .destructive) { Task { await vm.staffAction("suspend_staff", staffID: s.id) } }
                                    } else {
                                        Button("Reactivate") { Task { await vm.staffAction("reactivate_staff", staffID: s.id) } }
                                    }
                                } label: { Image(systemName: "ellipsis.circle") }
                            }
                        }
                    } header: { Text("Staff") } footer: {
                        Text("Reset device lets a staffer re-bind their phone; suspend blocks their login.")
                    }
                }

                Section {
                    Button { Task { await vm.impersonate() } } label: {
                        Label("Impersonate owner (link)", systemImage: "person.fill.viewfinder")
                    }
                    Button { Task { await vm.account("reset_password") } } label: {
                        Label("Send password reset", systemImage: "key.horizontal")
                    }
                    Button { showEmailPrompt = true } label: {
                        Label("Change owner email", systemImage: "envelope.badge")
                    }
                    Button(role: .destructive) { confirmDisable = true } label: {
                        Label("Disable owner login", systemImage: "person.crop.circle.badge.xmark")
                    }
                    Button { Task { await vm.account("enable") } } label: {
                        Label("Re-enable owner login", systemImage: "person.crop.circle.badge.checkmark")
                    }
                    Button(role: .destructive) { confirmOffboard = true } label: {
                        Label("Offboard (cancel plan)", systemImage: "xmark.octagon")
                    }
                } header: { Text("Account") } footer: {
                    Text("Members' data and earned rewards are untouched by these actions.")
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
        .confirmationDialog("Offboard this merchant?", isPresented: $confirmOffboard, titleVisibility: .visible) {
            Button("Offboard & cancel plan", role: .destructive) { Task { await vm.account("offboard") } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Disables the owner login and sets billing to cancelled.") }
        .alert("Change owner email", isPresented: $showEmailPrompt) {
            TextField("new@email.com", text: $newEmail)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            Button("Update") {
                let e = newEmail.trimmingCharacters(in: .whitespaces)
                if !e.isEmpty { Task { await vm.account("change_email", email: e) } }
                newEmail = ""
            }
            Button("Cancel", role: .cancel) { newEmail = "" }
        } message: { Text("The owner will sign in with this email going forward.") }
        .task {
            await vm.load()
            if let m = vm.detail?.merchant {
                plan = AdminPlanTier(rawValue: m.planTier ?? "starter") ?? .starter
                billing = AdminBilling(rawValue: m.billingStatus ?? "active") ?? .active
            }
        }
    }
}
