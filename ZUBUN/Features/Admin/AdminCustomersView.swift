//
//  AdminCustomersView.swift
//  ZUBUN
//
//  Admin → Customer lookup (6D): search by phone/email/name → cards + reward
//  tokens (redemptions audit), with the ability to void a live token.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AdminCustomersViewModel {
    var query = ""
    var results: [AdminCustomerRow] = []
    var isLoading = false
    private let service = AdminService()

    func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        isLoading = true; defer { isLoading = false }
        results = (try? await service.customerSearch(q: q)) ?? []
    }
}

struct AdminCustomersView: View {
    @State private var vm = AdminCustomersViewModel()

    var body: some View {
        List {
            if vm.results.isEmpty && !vm.isLoading {
                Text("Search by phone, email, or name.").foregroundStyle(.secondary)
            }
            ForEach(vm.results) { c in
                NavigationLink { AdminCustomerDetailView(customerID: c.id, title: c.name ?? c.phone ?? "Customer") } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name ?? c.phone ?? "—").font(.headline)
                        Text([c.phone, c.email].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(Text("Customer lookup", comment: "Admin customers title"))
        .searchable(text: $vm.query, prompt: Text("Phone, email, or name"))
        .onSubmit(of: .search) { Task { await vm.search() } }
    }
}

@MainActor
@Observable
final class AdminCustomerDetailViewModel {
    var detail: AdminCustomerDetail?
    var banner: (InlineBanner.Kind, String)?
    let customerID: String
    private let service = AdminService()
    init(customerID: String) { self.customerID = customerID }

    func load() async { detail = try? await service.customer(id: customerID) }

    /// Void a live reward token — resolves its venue from the matching card.
    func voidToken(_ token: AdminRewardToken) async {
        guard let venueID = detail?.cards.first(where: { $0.id == token.membershipId })?.venueId else {
            banner = (.error, "Couldn't resolve venue"); return
        }
        do { try await service.voidReward(tokenID: token.id, venueID: venueID); banner = (.info, "Reward voided."); await load() }
        catch { banner = (.error, "Void failed") }
    }
}

struct AdminCustomerDetailView: View {
    let title: String
    @State private var vm: AdminCustomerDetailViewModel

    init(customerID: String, title: String) {
        self.title = title
        _vm = State(initialValue: AdminCustomerDetailViewModel(customerID: customerID))
    }

    var body: some View {
        List {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            if let c = vm.detail?.customer {
                Section("Customer") {
                    if let p = c.phone { LabeledContent("Phone", value: p) }
                    if let e = c.email { LabeledContent("Email", value: e) }
                    if let e = c.erasureStatus, e != "active" { LabeledContent("Status", value: e) }
                }
            }

            Section("Cards") {
                if (vm.detail?.cards ?? []).isEmpty { Text("No cards.").foregroundStyle(.secondary) }
                ForEach(vm.detail?.cards ?? []) { card in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.venueName ?? "—").font(.subheadline.weight(.semibold))
                        Text("\(card.stamps ?? 0) stamps · \(card.tier ?? "") · \(card.cardState ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Reward tokens") {
                if (vm.detail?.tokens ?? []).isEmpty { Text("No rewards issued.").foregroundStyle(.secondary) }
                ForEach(vm.detail?.tokens ?? []) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.status ?? "—").font(.subheadline.weight(.semibold))
                            if let d = DubaiDate.parseISO(t.createdAt) {
                                Text("Issued \(DubaiDate.shortDate(d))").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if t.isActive {
                            Button("Void", role: .destructive) { Task { await vm.voidToken(t) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(title))
        .zInlineTitle()
        .task { await vm.load() }
    }
}
