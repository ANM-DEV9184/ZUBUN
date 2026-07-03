//
//  AdminFinanceView.swift
//  ZUBUN
//
//  Admin → Revenue & metering (6C): MRR, billing-status mix, per-merchant
//  message usage. Reached from the dashboard.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AdminFinanceViewModel {
    var finance: AdminFinance?
    var isLoading = false
    private let service = AdminService()
    func load() async {
        isLoading = true; defer { isLoading = false }
        finance = try? await service.finance()
    }
}

struct AdminFinanceView: View {
    @State private var vm = AdminFinanceViewModel()

    var body: some View {
        List {
            Section {
                HStack {
                    Text("MRR").font(.headline)
                    Spacer()
                    Text("AED \(vm.finance?.mrr ?? 0)").font(.brandTitle()).foregroundStyle(Brand.orange)
                }
            } footer: { Text("Monthly recurring revenue from active paid plans.") }

            if let p = vm.finance?.paying {
                Section("Paying merchants") {
                    LabeledContent("Starter", value: "\(p.starter ?? 0)")
                    LabeledContent("Standard", value: "\(p.standard ?? 0)")
                    LabeledContent("Multi", value: "\(p.multi ?? 0)")
                }
            }
            if let s = vm.finance?.byStatus {
                Section("Billing status") {
                    LabeledContent("Trialing", value: "\(s.trialing ?? 0)")
                    LabeledContent("Active", value: "\(s.active ?? 0)")
                    LabeledContent("Past due", value: "\(s.pastDue ?? 0)")
                    LabeledContent("Cancelled", value: "\(s.cancelled ?? 0)")
                }
            }

            Section("Message usage (top 50)") {
                if (vm.finance?.metering ?? []).isEmpty {
                    Text("No usage yet.").foregroundStyle(.secondary)
                }
                ForEach(vm.finance?.metering ?? []) { m in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(m.name ?? "—").font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text((m.planTier ?? "").capitalized).font(.caption2).foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(m.used ?? 0), total: Double(max(m.allowance ?? 1, 1)))
                            .tint(Brand.orange)
                        Text("\(m.used ?? 0) / \(m.allowance ?? 0) used · \(m.remaining ?? 0) left")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle(Text("Revenue & metering", comment: "Admin finance title"))
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }
}
