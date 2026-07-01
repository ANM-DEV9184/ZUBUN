//
//  PayrollView.swift
//  ZUBUN
//
//  Owner → Payroll (spec C11): pay setup per staff, generate payslips, view slips,
//  adjustments, mark paid. All direct owner-JWT calls.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class PayrollViewModel {
    var month: String = DubaiDate.monthString(Date())
    var staff: [OwnerStaff] = []
    var configs: [PayConfig] = []
    var slips: [Payslip] = []
    var adjustments: [PayslipAdjustment] = []
    var banner: (InlineBanner.Kind, String)?
    var isLoading = false

    private var venueID: String?
    private let service = OwnerService()

    var months: [String] { DubaiDate.recentMonths(6) }
    var monthSlips: [Payslip] { slips.filter { ($0.periodMonth ?? "").hasPrefix(month) } }

    func staffName(_ id: String) -> String { staff.first { $0.id == id }?.name ?? "Staff" }
    func config(for staffID: String) -> PayConfig? { configs.first { $0.staffId == staffID } }
    func adjustments(for slipID: String) -> [PayslipAdjustment] { adjustments.filter { $0.payslipId == slipID } }

    func load(venueID: String) async {
        self.venueID = venueID
        isLoading = true; defer { isLoading = false }
        staff = (try? await service.venueStaff(venueID: venueID))?.filter { $0.isActive } ?? []
        configs = (try? await service.payConfigs(venueID: venueID)) ?? []
        slips = (try? await service.payslips(venueID: venueID)) ?? []
        adjustments = (try? await service.adjustments(payslipIDs: slips.map(\.id))) ?? []
    }

    func generate() async {
        guard let v = venueID else { return }
        do {
            let res = try await service.generatePayslips(venueID: v, month: month)
            banner = (.info, res.result == "ok" ? String(localized: "payroll.generated", defaultValue: "Payslips generated") : (res.result ?? "Done"))
            await load(venueID: v)
        } catch { banner = (.error, error.localizedDescription) }
    }

    func saveConfig(staffID: String, payType: String, baseRate: Double, otMult: Double,
                    payday: Int, premiumMult: Double, deduct: Bool) async {
        guard let v = venueID else { return }
        try? await service.upsertPayConfig(venueID: v, staffID: staffID, payType: payType, baseRate: baseRate,
                                           overtimeMultiplier: otMult, paydayDom: payday, premiumMultiplier: premiumMult,
                                           deductAbsences: deduct)
        configs = (try? await service.payConfigs(venueID: v)) ?? configs
    }

    func addAdjustment(slipID: String, label: String, amount: Double) async {
        _ = try? await service.addAdjustment(payslipID: slipID, label: label, amount: amount, note: nil)
        if let v = venueID { await load(venueID: v) }
    }
    func removeAdjustment(id: String) async {
        _ = try? await service.removeAdjustment(id: id)
        if let v = venueID { await load(venueID: v) }
    }
    func markPaid(slipID: String) async {
        _ = try? await service.markPayslipPaid(id: slipID)
        if let v = venueID { await load(venueID: v) }
    }
}

struct PayrollView: View {
    @State private var vm = PayrollViewModel()
    @State private var context = OwnerContext.shared
    @State private var editStaff: OwnerStaff?
    @State private var openSlip: Payslip?

    var body: some View {
        Form {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            Section {
                Picker("Month", selection: $vm.month) {
                    ForEach(vm.months, id: \.self) { Text($0).tag($0) }
                }
                Button("Generate payslips") { Task { await vm.generate() } }
            }

            Section("Pay setup") {
                ForEach(vm.staff) { s in
                    Button { editStaff = s } label: {
                        HStack {
                            Text(s.name)
                            Spacer()
                            if let c = vm.config(for: s.id) {
                                Text("\(c.payType ?? "monthly") · \(Int(c.baseRate ?? 0)) AED").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Set up").font(.caption).foregroundStyle(Brand.orange)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Payslips · \(vm.month)") {
                if vm.monthSlips.isEmpty {
                    Text("No payslips — generate for this month.").foregroundStyle(.secondary)
                }
                ForEach(vm.monthSlips) { slip in
                    Button { openSlip = slip } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(vm.staffName(slip.staffId)).font(.headline)
                                Text((slip.status ?? "").capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(slip.net)) \(slip.currency ?? "AED")").font(.subheadline.monospacedDigit())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(Text("Payroll", comment: "Payroll title"))
        .toolbar { VenueSwitcher(context: context) }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.load(venueID: v) }
        }
        .sheet(item: $editStaff) { s in
            PayConfigSheet(staffName: s.name, config: vm.config(for: s.id)) { pt, rate, ot, payday, prem, deduct in
                Task { await vm.saveConfig(staffID: s.id, payType: pt, baseRate: rate, otMult: ot, payday: payday, premiumMult: prem, deduct: deduct) }
            }
        }
        .sheet(item: $openSlip) { slip in
            PayslipDetailSheet(slip: slip, staffName: vm.staffName(slip.staffId),
                               adjustments: vm.adjustments(for: slip.id),
                               onAddAdjustment: { l, a in Task { await vm.addAdjustment(slipID: slip.id, label: l, amount: a) } },
                               onRemoveAdjustment: { id in Task { await vm.removeAdjustment(id: id) } },
                               onMarkPaid: { Task { await vm.markPaid(slipID: slip.id) } })
        }
    }
}

struct PayConfigSheet: View {
    let staffName: String
    let config: PayConfig?
    var onSave: (String, Double, Double, Int, Double, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var payType = "monthly"
    @State private var rate = ""
    @State private var otMult = "1.25"
    @State private var payday = 1
    @State private var premiumMult = "1.5"
    @State private var deduct = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Pay type", selection: $payType) { Text("Monthly").tag("monthly"); Text("Hourly").tag("hourly") }
                TextField(payType == "monthly" ? "Monthly salary (AED)" : "Hourly rate (AED)", text: $rate).zKeyboard(.number)
                TextField("Overtime multiplier", text: $otMult).zKeyboard(.number)
                Stepper("Payday (day of month): \(payday)", value: $payday, in: 1...28)
                TextField("Holiday premium multiplier", text: $premiumMult).zKeyboard(.number)
                Toggle("Deduct unpaid absences", isOn: $deduct)
            }
            .navigationTitle(Text(verbatim: staffName))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(payType, Double(rate) ?? 0, Double(otMult) ?? 1.25, payday, Double(premiumMult) ?? 1.5, deduct)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let c = config {
                    payType = c.payType ?? "monthly"
                    rate = String(Int(c.baseRate ?? 0))
                    otMult = String(c.overtimeMultiplier ?? 1.25)
                    payday = c.paydayDom ?? 1
                    premiumMult = String(c.premiumMultiplier ?? 1.5)
                    deduct = c.deductAbsences ?? false
                }
            }
        }
    }
}

struct PayslipDetailSheet: View {
    let slip: Payslip
    let staffName: String
    let adjustments: [PayslipAdjustment]
    var onAddAdjustment: (String, Double) -> Void
    var onRemoveAdjustment: (String) -> Void
    var onMarkPaid: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var adjLabel = ""
    @State private var adjAmount = ""
    @State private var adjSign = 1.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Status", value: (slip.status ?? "").capitalized)
                    LabeledContent("Gross", value: "\(Int(slip.grossAmount ?? 0)) \(slip.currency ?? "AED")")
                    LabeledContent("Adjustments", value: "\(Int(slip.adjustmentTotal ?? 0))")
                    LabeledContent("Net", value: "\(Int(slip.net)) \(slip.currency ?? "AED")")
                    LabeledContent("Regular", value: "\(slip.regularMinutes ?? 0) min")
                    LabeledContent("Overtime", value: "\(slip.overtimeMinutes ?? 0) min")
                }

                Section("Adjustments") {
                    ForEach(adjustments) { a in
                        HStack {
                            Text(a.label); Spacer()
                            Text("\(a.amount >= 0 ? "+" : "")\(Int(a.amount))").foregroundStyle(a.amount >= 0 ? Brand.success : Brand.danger)
                        }
                        .swipeActions { Button(role: .destructive) { onRemoveAdjustment(a.id) } label: { Label("Remove", systemImage: "trash") } }
                    }
                    HStack {
                        TextField("Label", text: $adjLabel)
                        Picker("", selection: $adjSign) { Text("+").tag(1.0); Text("−").tag(-1.0) }.labelsHidden().frame(width: 60)
                        TextField("Amount", text: $adjAmount).zKeyboard(.number).frame(width: 80)
                        Button("Add") {
                            if let a = Double(adjAmount) { onAddAdjustment(adjLabel, a * adjSign); adjLabel = ""; adjAmount = "" }
                        }.disabled(adjLabel.isEmpty || adjAmount.isEmpty)
                    }
                }

                if slip.status == "finalized" || slip.status == "draft" {
                    Section { Button("Mark paid") { onMarkPaid(); dismiss() } }
                }
            }
            .navigationTitle(Text(verbatim: staffName))
            .zInlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
