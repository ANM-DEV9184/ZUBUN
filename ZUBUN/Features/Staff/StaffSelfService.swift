//
//  StaffSelfService.swift
//  ZUBUN
//
//  Staff self-service reads (Phase 6): attendance history (+ flag an entry) and
//  payslips (+ confirm / dispute). Backed by the new GET /api/staff/{attendance,
//  payslips} routes.
//

import SwiftUI
import Observation

// MARK: - Helpers

private func staffMinutesLabel(_ minutes: Int?) -> String {
    guard let m = minutes, m > 0 else { return "0m" }
    return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
}

private func staffMonthLabel(_ ymd: String?) -> String {
    guard let ymd else { return "—" }
    let inF = DateFormatter(); inF.calendar = Calendar(identifier: .gregorian)
    inF.dateFormat = "yyyy-MM-dd"; inF.timeZone = TimeZone(identifier: "Asia/Dubai")
    guard let d = inF.date(from: ymd) else { return ymd }
    let out = DateFormatter(); out.dateFormat = "MMMM yyyy"; out.timeZone = TimeZone(identifier: "Asia/Dubai")
    return out.string(from: d)
}

private func staffDateLabel(_ ymd: String?) -> String {
    guard let ymd else { return "—" }
    let inF = DateFormatter(); inF.calendar = Calendar(identifier: .gregorian)
    inF.dateFormat = "yyyy-MM-dd"; inF.timeZone = TimeZone(identifier: "Asia/Dubai")
    guard let d = inF.date(from: ymd) else { return ymd }
    let out = DateFormatter(); out.dateFormat = "EEE d MMM"; out.timeZone = TimeZone(identifier: "Asia/Dubai")
    return out.string(from: d)
}

private func staffAmountLabel(_ amount: Double?, _ currency: String?) -> String {
    guard let amount else { return "—" }
    let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
    let n = f.string(from: NSNumber(value: amount)) ?? "\(amount)"
    return "\(currency ?? "AED") \(n)"
}

// MARK: - Attendance history

struct AttendanceHistoryView: View {
    @State private var entries: [StaffAttendanceEntry] = []
    @State private var loading = false
    @State private var flagTarget: StaffAttendanceEntry?
    @State private var banner: String?
    private let service = StaffService()

    var body: some View {
        List {
            if let banner { Section { Text(banner).foregroundStyle(.secondary) } }
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(staffDateLabel(e.workDate)).font(.headline)
                        Spacer()
                        Text(staffMinutesLabel(e.paidWorkedMinutes ?? e.workedMinutes))
                            .font(.subheadline.monospacedDigit())
                    }
                    HStack(spacing: 8) {
                        if let i = DubaiDate.parseISO(e.clockInAt) { Text(DubaiDate.time(i)) }
                        if let o = DubaiDate.parseISO(e.clockOutAt) { Text("→ \(DubaiDate.time(o))") }
                        if (e.overtimeMinutes ?? 0) > 0 {
                            Text("OT \(staffMinutesLabel(e.overtimeMinutes))").foregroundStyle(Brand.orange)
                        }
                        if let el = e.earlyLeaveMinutes, el > 0 { Text("early \(el)m").foregroundStyle(Brand.warning) }
                        if let la = e.lateMinutes, la > 0 { Text("late \(la)m").foregroundStyle(Brand.warning) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    if e.entryId != nil {
                        Button { flagTarget = e } label: { Label("Flag", systemImage: "flag") }.tint(Brand.orange)
                    }
                }
            }
            if entries.isEmpty && !loading {
                Text("No attendance in the last 5 weeks.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("My attendance", comment: "Attendance history title"))
        .overlay { if loading && entries.isEmpty { LoadingState() } }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $flagTarget) { entry in
            FlagEntrySheet(dateLabel: staffDateLabel(entry.workDate)) { note in
                Task {
                    _ = try? await service.flagAttendance(entryID: entry.entryId ?? "", note: note)
                    banner = String(localized: "attendance.flagged", defaultValue: "Reported to your manager.")
                }
            }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        entries = ((try? await service.attendance())?.entries ?? []).filter { !$0.isNoShow }
    }
}

private struct FlagEntrySheet: View {
    let dateLabel: String
    var onSubmit: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "attendance.flag.what", defaultValue: "What's wrong with \(dateLabel)?")) {
                    TextField("Describe the issue (optional)", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(Text("Flag entry", comment: "Flag entry title")).zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onSubmit(note.isEmpty ? nil : note); dismiss() }
                }
            }
        }
    }
}

// MARK: - Payslips

struct PayslipsView: View {
    @State private var data: StaffPayslipsResponse?
    @State private var loading = false
    private let service = StaffService()

    var body: some View {
        List {
            ForEach(data?.payslips ?? []) { p in
                NavigationLink {
                    PayslipDetailView(payslip: p, adjustments: (data?.adjustments ?? []).filter { $0.payslipId == p.id })
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(staffMonthLabel(p.periodMonth)).font(.headline)
                            Text(p.status?.capitalized ?? "—")
                                .font(.caption).foregroundStyle(p.isPaid ? Brand.success : .secondary)
                        }
                        Spacer()
                        Text(staffAmountLabel(p.grossAmount, p.currency)).font(.subheadline.monospacedDigit())
                    }
                }
            }
            if (data?.payslips.isEmpty ?? true) && !loading {
                Text("No payslips yet.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("My pay", comment: "Payslips title"))
        .overlay { if loading && data == nil { LoadingState() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        loading = true; defer { loading = false }
        data = try? await service.payslips()
    }
}

struct PayslipDetailView: View {
    let payslip: StaffPayslip
    let adjustments: [PayAdjustment]
    @State private var banner: String?
    @State private var showDispute = false
    private let service = StaffService()

    var body: some View {
        List {
            Section {
                LabeledContent("Period", value: staffMonthLabel(payslip.periodMonth))
                LabeledContent("Gross", value: staffAmountLabel(payslip.grossAmount, payslip.currency))
                if let a = payslip.adjustmentTotal, a != 0 {
                    LabeledContent("Adjustments", value: staffAmountLabel(a, payslip.currency))
                }
                LabeledContent("Regular", value: staffMinutesLabel(payslip.regularMinutes))
                if (payslip.overtimeMinutes ?? 0) > 0 {
                    LabeledContent("Overtime", value: staffMinutesLabel(payslip.overtimeMinutes))
                }
                LabeledContent("Status", value: payslip.status?.capitalized ?? "—")
            }

            if !adjustments.isEmpty {
                Section(String(localized: "pay.adjustments", defaultValue: "Adjustments")) {
                    ForEach(adjustments) { adj in
                        HStack {
                            Text(adj.label ?? "Adjustment")
                            Spacer()
                            Text(staffAmountLabel(adj.amount, payslip.currency)).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Confirm payslip") {
                    Task {
                        let r = try? await service.payslip(id: payslip.id, dispute: false, note: nil)
                        banner = (r?.result ?? .ok).userMessage
                    }
                }
                Button("Dispute", role: .destructive) { showDispute = true }
            }

            if let banner { Section { Text(banner).foregroundStyle(.secondary) } }
        }
        .navigationTitle(Text("Payslip", comment: "Payslip detail title"))
        .sheet(isPresented: $showDispute) {
            FlagEntrySheet(dateLabel: staffMonthLabel(payslip.periodMonth)) { note in
                Task {
                    let r = try? await service.payslip(id: payslip.id, dispute: true, note: note)
                    banner = (r?.result ?? .ok).userMessage
                }
            }
        }
    }
}
