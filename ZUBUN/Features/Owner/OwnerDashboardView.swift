//
//  OwnerDashboardView.swift
//  ZUBUN
//
//  Owner overview (spec §4.3 / C2): KPI tiles + the repeat-stamp approval queue
//  with approve/deny (spec C3). Lighter pass — extends to members/rota/payroll.
//

import SwiftUI
import Observation
import Charts

enum TrendMetric: String, CaseIterable, Identifiable {
    case stamps = "Stamps"
    case newMembers = "New members"
    case rewards = "Rewards"
    var id: String { rawValue }
}

@MainActor
@Observable
final class OwnerDashboardViewModel {
    var kpis: OwnerKPIs?
    var approvals: [StampApproval] = []
    var billing: MerchantPlan?
    var venueKPIs: VenueKPIs?
    var daily: [DailyStat] = []
    var heat: [HeatCell] = []
    var metric: TrendMetric = .stamps
    var isLoading = false
    var error: String?
    private let service = OwnerService()

    /// Per-venue analytics for the trends section (charts + reward funnel).
    func loadVenue(_ venueID: String) async {
        async let k = service.venueKPIs(venueID: venueID)
        async let d = service.venueDailyStats(venueID: venueID, days: 30)
        async let h = service.venueHeatmap(venueID: venueID, days: 30)
        venueKPIs = try? await k
        daily = (try? await d) ?? []
        heat = (try? await h) ?? []
    }

    func value(_ s: DailyStat) -> Int {
        switch metric {
        case .stamps: return s.stamps ?? 0
        case .newMembers: return s.newMembers ?? 0
        case .rewards: return s.rewards ?? 0
        }
    }

    /// A dunning banner to show on the overview, if any.
    var billingWarning: (InlineBanner.Kind, String)? {
        switch billing?.billingStatus {
        case "past_due":
            return (.warning, String(localized: "billing.past_due", defaultValue: "Payment failed — please update your card. Your program keeps running during the grace period."))
        case "cancelled":
            return (.error, String(localized: "billing.cancelled", defaultValue: "Subscription paused. Customers can still redeem rewards they've earned, but new stamps are paused until you reactivate."))
        default:
            return nil
        }
    }

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            billing = try? await service.merchantPlan()
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
    @State private var context = OwnerContext.shared
    private let session = SessionStore.shared

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let warning = vm.billingWarning {
                    InlineBanner(kind: warning.0, message: warning.1)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    KPITile(title: "Members", value: vm.kpis?.members)
                    KPITile(title: "Active cards", value: vm.kpis?.activeCards)
                    KPITile(title: "Stamps today", value: vm.kpis?.stampsToday)
                    KPITile(title: "Stamps 30d", value: vm.kpis?.stamps30d)
                }

                // Multi-venue rollup — compare venues (only when there's more than one).
                if let pv = vm.kpis?.perVenue, pv.count > 1 {
                    CardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Stamps by venue · 7 days", comment: "Multi-venue rollup title").font(.brandHeadline())
                            Chart(pv) { v in
                                BarMark(
                                    x: .value("Stamps", v.stamps7d ?? 0),
                                    y: .value("Venue", v.name)
                                )
                                .foregroundStyle(Brand.orange)
                                .annotation(position: .trailing) {
                                    Text("\(v.stamps7d ?? 0)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .frame(height: CGFloat(pv.count) * 40 + 16)
                        }
                    }
                }

                trendsSection

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
            VenueSwitcher(context: context)
            ToolbarItem(placement: .primaryAction) {
                Button("Sign out") { Task { await OwnerService().signOut(); OwnerContext.shared.reset() } }
            }
        }
        .refreshable {
            await vm.load()
            if let v = context.selectedVenueID { await vm.loadVenue(v) }
        }
        .task { await vm.load() }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.loadVenue(v) }
        }
    }

    // MARK: - Trends (Swift Charts)

    @ViewBuilder
    private var trendsSection: some View {
        if let k = vm.venueKPIs {
            HStack(spacing: 12) {
                TrendBadge(label: "Stamps · 30d", value: k.stamps30d ?? 0, delta: k.stampsDelta)
                TrendBadge(label: "New members · 7d", value: k.newMembers7d ?? 0, delta: k.newMembersDelta)
            }
        }

        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 30 days", comment: "Trends chart title").font(.brandHeadline())
                Picker("Metric", selection: $vm.metric) {
                    ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if vm.daily.isEmpty {
                    Text("No activity yet.", comment: "Empty chart")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    Chart(vm.daily) { s in
                        BarMark(
                            x: .value("Day", s.date, unit: .day),
                            y: .value(vm.metric.rawValue, vm.value(s))
                        )
                        .foregroundStyle(Brand.orange)
                    }
                    .frame(height: 180)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) {
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                }
            }
        }

        if !vm.heat.isEmpty {
            CardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Busiest times · 30 days", comment: "Heatmap title").font(.brandHeadline())
                    Chart(vm.heat) { c in
                        RectangleMark(
                            x: .value("Hour", c.hour),
                            y: .value("Day", c.weekdayLabel)
                        )
                        .foregroundStyle(by: .value("Stamps", c.count))
                    }
                    .chartForegroundStyleScale(range: Gradient(colors: [Brand.stone500.opacity(0.15), Brand.orange]))
                    .chartYScale(domain: ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"])
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                            AxisValueLabel { if let h = v.as(Int.self) { Text("\(h)h") } }
                        }
                    }
                    .frame(height: 200)
                }
            }
        }

        if let k = vm.venueKPIs {
            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rewards · 30 days", comment: "Reward funnel title").font(.brandHeadline())
                    LabeledContent("Issued", value: "\(k.rewardsIssued30d ?? 0)")
                    LabeledContent("Redeemed", value: "\(k.rewardsRedeemed30d ?? 0)")
                    if let rate = k.redemptionRate {
                        LabeledContent("Redemption rate", value: "\(rate)%")
                    }
                }
            }
        }
    }
}

struct TrendBadge: View {
    let label: String
    let value: Int
    let delta: Int?
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(value)").font(.brandTitle()).foregroundStyle(Brand.ink)
                HStack(spacing: 6) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    if let d = delta {
                        Label("\(abs(d))%", systemImage: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(d >= 0 ? Brand.success : Brand.danger)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                    HStack(spacing: 6) {
                        Text(approval.reasonLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Brand.amber.opacity(0.2), in: Capsule())
                            .foregroundStyle(Brand.ink)
                        if let staff = approval.staffName {
                            Text("by \(staff)").font(.caption).foregroundStyle(.secondary)
                        }
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

