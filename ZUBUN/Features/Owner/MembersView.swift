//
//  MembersView.swift
//  ZUBUN
//
//  Owner → Members (spec C4): roster + search + detail drawer + grant stamps.
//  RLS-scoped PostgREST reads; grant via owner RPC.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class MembersViewModel {
    var members: [MemberRow] = []
    var search = ""
    var isLoading = false
    var error: String?
    var canLoadMore = false

    private var offset = 0
    private var venueID: String?
    private let service = OwnerService()

    func reload(venueID: String) async {
        self.venueID = venueID
        offset = 0
        members = []
        canLoadMore = false
        await loadMore()
    }

    func loadMore() async {
        guard let venueID, !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let batch = try await service.members(venueID: venueID, search: search, offset: offset)
            members += batch
            offset += batch.count
            canLoadMore = batch.count >= 25
        } catch let e as APIError {
            error = e.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MembersView: View {
    @State private var vm = MembersViewModel()
    @State private var context = OwnerContext.shared
    @State private var selected: MemberRow?

    var body: some View {
        List {
            if let error = vm.error {
                InlineBanner(kind: .error, message: error)
            }
            ForEach(vm.members) { member in
                Button { selected = member } label: { MemberRowView(member: member) }
                    .buttonStyle(.plain)
            }
            if vm.canLoadMore {
                Button("Load more") { Task { await vm.loadMore() } }
                    .frame(maxWidth: .infinity)
            }
            if vm.members.isEmpty && !vm.isLoading {
                EmptyStateView(systemImage: "person.2",
                               title: String(localized: "members.empty", defaultValue: "No members"))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(Text("Members", comment: "Members title"))
        .toolbar { VenueSwitcher(context: context) }
        .searchable(text: $vm.search, prompt: Text("Name or phone"))
        .onSubmit(of: .search) {
            if let v = context.selectedVenueID { Task { await vm.reload(venueID: v) } }
        }
        .overlay { if vm.isLoading && vm.members.isEmpty { LoadingState() } }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.reload(venueID: v) }
        }
        .sheet(item: $selected) { member in
            MemberDetailSheet(member: member) { Task { if let v = context.selectedVenueID { await vm.reload(venueID: v) } } }
        }
    }
}

struct MemberRowView: View {
    let member: MemberRow
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(member.displayName).font(.headline)
                if member.customers?.nameOptional != nil, let phone = member.maskedPhone {
                    Text(phone).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let tier = member.tier { TierBadge(tier: tier) }
            Text("\(member.stampsCount ?? 0)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Brand.orange)
        }
        .padding(.vertical, 4)
    }
}
