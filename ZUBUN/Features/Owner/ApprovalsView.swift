//
//  ApprovalsView.swift
//  ZUBUN
//
//  Owner → Approvals (spec C7/C9/C10 + shift swaps): the leave, shift-swap,
//  day-off-change, and out-of-hours/overtime/device-reset queues, with
//  approve/deny. All via direct owner-JWT RPCs.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ApprovalsViewModel {
    enum Queue: String, CaseIterable, Identifiable {
        case leave, swaps, dayoff, access
        var id: String { rawValue }
        var title: String {
            switch self {
            case .leave:  return String(localized: "queue.leave", defaultValue: "Leave")
            case .swaps:  return String(localized: "queue.swaps", defaultValue: "Swaps")
            case .dayoff: return String(localized: "queue.dayoff", defaultValue: "Day-off")
            case .access: return String(localized: "queue.access", defaultValue: "Access")
            }
        }
    }

    var leave: [LeaveRequestRow] = []
    var swaps: [ShiftSwapRow] = []
    var dayoff: [DayoffRequestRow] = []
    var access: [AccessRequestRow] = []
    var isLoading = false
    var error: String?

    private let service = OwnerService()

    var totalCount: Int { leave.count + swaps.count + dayoff.count + access.count }

    func load(venueID: String) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        async let l = try? service.leaveRequests(venueID: venueID)
        async let s = try? service.shiftSwaps(venueID: venueID)
        async let d = try? service.dayoffRequests(venueID: venueID)
        async let a = try? service.accessRequests(venueID: venueID)
        leave = await l ?? []
        swaps = await s ?? []
        dayoff = await d ?? []
        access = await a ?? []
    }

    func decideLeave(_ row: LeaveRequestRow, approve: Bool) async {
        _ = try? await service.decideLeave(id: row.id, approve: approve)
        leave.removeAll { $0.id == row.id }
    }
    func decideSwap(_ row: ShiftSwapRow, approve: Bool) async {
        _ = try? await service.decideSwap(id: row.id, approve: approve)
        swaps.removeAll { $0.id == row.id }
    }
    func decideDayoff(_ row: DayoffRequestRow, approve: Bool) async {
        _ = try? await service.decideDayoff(id: row.id, approve: approve)
        dayoff.removeAll { $0.id == row.id }
    }
    func decideAccess(_ row: AccessRequestRow, approve: Bool) async {
        _ = try? await service.decideAccess(id: row.id, approve: approve)
        access.removeAll { $0.id == row.id }
    }
}

struct ApprovalsView: View {
    @State private var vm = ApprovalsViewModel()
    @State private var context = OwnerContext.shared
    @State private var queue: ApprovalsViewModel.Queue = .leave

    var body: some View {
        VStack(spacing: 0) {
            Picker("Queue", selection: $queue) {
                ForEach(ApprovalsViewModel.Queue.allCases) { q in Text(q.title).tag(q) }
            }
            .pickerStyle(.segmented)
            .padding()

            List {
                switch queue {
                case .leave:
                    queueBody(vm.leave, empty: "No leave requests") { row in
                        ApprovalCard(title: row.staffName ?? "Staff",
                                     subtitle: dateRange(row.fromDate, row.toDate) + " · " + (row.leaveType ?? ""),
                                     detail: row.reason,
                                     onApprove: { Task { await vm.decideLeave(row, approve: true) } },
                                     onDeny: { Task { await vm.decideLeave(row, approve: false) } })
                    }
                case .swaps:
                    queueBody(vm.swaps, empty: "No shift swaps") { row in
                        ApprovalCard(title: "\(row.fromName ?? "?") → \(row.toName ?? "?")",
                                     subtitle: (row.workDate ?? "") + " " + (row.startTime ?? ""),
                                     detail: row.reason,
                                     onApprove: { Task { await vm.decideSwap(row, approve: true) } },
                                     onDeny: { Task { await vm.decideSwap(row, approve: false) } })
                    }
                case .dayoff:
                    queueBody(vm.dayoff, empty: "No day-off changes") { row in
                        ApprovalCard(title: row.staffName ?? "Staff",
                                     subtitle: "\(row.fromDate ?? "") → \(row.toDate ?? "")",
                                     detail: row.reason,
                                     onApprove: { Task { await vm.decideDayoff(row, approve: true) } },
                                     onDeny: { Task { await vm.decideDayoff(row, approve: false) } })
                    }
                case .access:
                    queueBody(vm.access, empty: "No access requests") { row in
                        ApprovalCard(title: row.staffName ?? "Staff",
                                     subtitle: row.kindLabel,
                                     detail: row.reason,
                                     onApprove: { Task { await vm.decideAccess(row, approve: true) } },
                                     onDeny: { Task { await vm.decideAccess(row, approve: false) } })
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(Text("Approvals", comment: "Approvals title"))
        .toolbar { VenueSwitcher(context: context) }
        .overlay { if vm.isLoading { LoadingState() } }
        .refreshable { if let v = context.selectedVenueID { await vm.load(venueID: v) } }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.load(venueID: v) }
        }
    }

    @ViewBuilder
    private func queueBody<Row: Identifiable, Content: View>(
        _ rows: [Row], empty: String, @ViewBuilder card: @escaping (Row) -> Content
    ) -> some View {
        if rows.isEmpty {
            EmptyStateView(systemImage: "checkmark.circle", title: empty)
                .listRowSeparator(.hidden)
        } else {
            ForEach(rows) { row in card(row) }
        }
    }

    private func dateRange(_ from: String?, _ to: String?) -> String {
        guard let from else { return "" }
        return to.map { "\(from) → \($0)" } ?? from
    }
}

struct ApprovalCard: View {
    let title: String
    let subtitle: String
    var detail: String?
    var onApprove: () -> Void
    var onDeny: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: onDeny) { Image(systemName: "xmark.circle.fill").foregroundStyle(Brand.danger) }
                .font(.title2).buttonStyle(.plain)
            Button(action: onApprove) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.success) }
                .font(.title2).buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}
