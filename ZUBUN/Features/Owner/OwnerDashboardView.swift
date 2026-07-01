//
//  OwnerDashboardView.swift
//  ZUBUN
//
//  Owner overview (spec §4.3 / C2): KPI tiles + the repeat-stamp approval queue
//  with approve/deny (spec C3). Lighter pass — extends to members/rota/payroll.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class OwnerDashboardViewModel {
    var kpis: OwnerKPIs?
    var approvals: [StampApproval] = []
    var isLoading = false
    var error: String?
    private let service = OwnerService()

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let k = try await service.kpis()
            kpis = k
            // Fetch the approval queue for each venue and merge.
            var merged: [StampApproval] = []
            for venue in k.perVenue ?? [] {
                if let rows = try? await service.stampApprovals(venueID: venue.venueId) {
                    merged.append(contentsOf: rows)
                }
            }
            approvals = merged.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        } catch let e as APIError {
            error = e.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    func decide(_ approval: StampApproval, approve: Bool) async {
        _ = try? await service.decideStampApproval(requestID: approval.id, approve: approve)
        approvals.removeAll { $0.id == approval.id }
    }
}

struct OwnerDashboardView: View {
    @State private var vm = OwnerDashboardViewModel()
    private let session = SessionStore.shared

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: columns, spacing: 12) {
                    KPITile(title: "Members", value: vm.kpis?.members)
                    KPITile(title: "Active cards", value: vm.kpis?.activeCards)
                    KPITile(title: "Stamps today", value: vm.kpis?.stampsToday)
                    KPITile(title: "Stamps 30d", value: vm.kpis?.stamps30d)
                }

                if let error = vm.error { InlineBanner(kind: .warning, message: error) }

                Text("Stamp approvals", comment: "Approvals section").font(.brandHeadline())
                if vm.approvals.isEmpty {
                    Text("No pending approvals", comment: "No approvals").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.approvals) { a in
                        ApprovalRow(approval: a,
                                    onApprove: { Task { await vm.decide(a, approve: true) } },
                                    onDeny: { Task { await vm.decide(a, approve: false) } })
                    }
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text("Dashboard", comment: "Owner dashboard title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Sign out") { Task { await OwnerService().signOut(); OwnerContext.shared.reset() } }
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }
}

struct KPITile: View {
    let title: String
    let value: Int?
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text(value.map(String.init) ?? "—").font(.brandTitle()).foregroundStyle(Brand.ink)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct ApprovalRow: View {
    let approval: StampApproval
    var onApprove: () -> Void
    var onDeny: () -> Void
    var body: some View {
        CardContainer {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(approval.customerName ?? approval.maskedPhone ?? "Customer").font(.headline)
                    if let staff = approval.staffName {
                        Text("by \(staff)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onDeny) { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.danger) }
                    .font(.title2)
                Button(action: onApprove) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success) }
                    .font(.title2)
            }
        }
    }
}

