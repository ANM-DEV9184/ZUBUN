//
//  TeamView.swift
//  ZUBUN
//
//  Owner → Team: segmented Rota / Live attendance (spec C6/C8). Live shows who's
//  on shift now, completed shifts, no-shows, and missed-clock-in reports; entries
//  can be deleted and reports resolved. (Manual add/adjust entry: next pass.)
//

import SwiftUI
import Observation

@MainActor
@Observable
final class LiveAttendanceViewModel {
    var rows: [AttendanceRow] = []
    var reports: [ClockinReportRow] = []
    var staff: [OwnerStaff] = []
    var isLoading = false
    var error: String?
    private var venueID: String?
    private let service = OwnerService()

    var onShift: [AttendanceRow] { rows.filter { $0.isOpen } }
    var completed: [AttendanceRow] { rows.filter { $0.status == "closed" || $0.status == "auto_closed" } }
    var awaiting: [AttendanceRow] { rows.filter { $0.isNoShow } }

    func load(venueID: String) async {
        self.venueID = venueID
        isLoading = true; error = nil
        defer { isLoading = false }
        let today = DubaiDate.todayString()
        async let a = try? service.attendanceDetail(venueID: venueID, from: today, to: today)
        async let r = try? service.clockinReports(venueID: venueID)
        async let s = try? service.venueStaff(venueID: venueID)
        rows = await a ?? []
        reports = await r ?? []
        staff = (await s ?? []).filter { $0.isActive }
    }

    func createEntry(staffID: String, day: Date, inTime: Date, outTime: Date?, note: String?) async {
        let outISO = outTime.map { DubaiDate.combineISO(day: day, time: $0) }
        _ = try? await service.createTimeEntry(staffID: staffID, workDate: DubaiDate.ymdString(day),
                                               clockInISO: DubaiDate.combineISO(day: day, time: inTime),
                                               clockOutISO: outISO, note: note)
        if let v = venueID { await load(venueID: v) }
    }

    func adjustEntry(_ row: AttendanceRow, day: Date, inTime: Date, outTime: Date) async {
        guard let id = row.entryId else { return }
        _ = try? await service.adjustTimeEntry(entryID: id,
                                               clockInISO: DubaiDate.combineISO(day: day, time: inTime),
                                               clockOutISO: DubaiDate.combineISO(day: day, time: outTime),
                                               status: "closed", overtimeStatus: nil, note: nil)
        if let v = venueID { await load(venueID: v) }
    }

    func deleteEntry(_ row: AttendanceRow) async {
        guard let id = row.entryId else { return }
        _ = try? await service.deleteEntry(id: id)
        if let v = venueID { await load(venueID: v) }
    }

    func resolve(_ report: ClockinReportRow) async {
        _ = try? await service.resolveClockinReport(id: report.id)
        reports.removeAll { $0.id == report.id }
    }

    static func durationLabel(_ minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return "0m" }
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

struct LiveAttendanceView: View {
    @Bindable var vm: LiveAttendanceViewModel
    @State private var showAddEntry = false
    @State private var adjustRow: AttendanceRow?

    var body: some View {
        List {
            if let error = vm.error { InlineBanner(kind: .error, message: error) }

            Section {
                Button { showAddEntry = true } label: { Label("Add manual entry", systemImage: "plus") }
            }

            section(String(localized: "live.on_shift", defaultValue: "On shift now"), vm.onShift, accent: Brand.success)
            section(String(localized: "live.completed", defaultValue: "Completed today"), vm.completed, accent: Brand.stone500)
            if !vm.awaiting.isEmpty {
                section(String(localized: "live.awaiting", defaultValue: "No-show / awaiting"), vm.awaiting, accent: Brand.warning)
            }

            if !vm.reports.isEmpty {
                Section(String(localized: "live.reports", defaultValue: "Missed clock-in reports")) {
                    ForEach(vm.reports) { r in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.staffName ?? "Staff").font(.headline)
                                if let note = r.note, !note.isEmpty {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Resolve") { Task { await vm.resolve(r) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if vm.rows.isEmpty && vm.reports.isEmpty && !vm.isLoading {
                EmptyStateView(systemImage: "clock", title: String(localized: "live.empty", defaultValue: "No attendance today"))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .overlay { if vm.isLoading && vm.rows.isEmpty { LoadingState() } }
        .sheet(isPresented: $showAddEntry) {
            AddEntrySheet(staff: vm.staff) { sid, day, inT, outT, note in
                Task { await vm.createEntry(staffID: sid, day: day, inTime: inT, outTime: outT, note: note) }
            }
        }
        .sheet(item: $adjustRow) { row in
            AdjustEntrySheet(row: row) { day, inT, outT in
                Task { await vm.adjustEntry(row, day: day, inTime: inT, outTime: outT) }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [AttendanceRow], accent: Color) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Circle().fill(accent).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name ?? "Staff").font(.headline)
                            HStack(spacing: 8) {
                                if let inAt = DubaiDate.parseISO(row.clockInAt) {
                                    Text(DubaiDate.time(inAt)).font(.caption).foregroundStyle(.secondary)
                                }
                                if let out = DubaiDate.parseISO(row.clockOutAt) {
                                    Text("→ \(DubaiDate.time(out))").font(.caption).foregroundStyle(.secondary)
                                }
                                if (row.overtimeMinutes ?? 0) > 0 {
                                    Text("OT \(LiveAttendanceViewModel.durationLabel(row.overtimeMinutes))")
                                        .font(.caption2).foregroundStyle(Brand.orange)
                                }
                            }
                        }
                        Spacer()
                        if !row.isNoShow {
                            Text(LiveAttendanceViewModel.durationLabel(row.paidWorkedMinutes ?? row.workedMinutes))
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                    .swipeActions {
                        if row.entryId != nil {
                            Button(role: .destructive) { Task { await vm.deleteEntry(row) } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { adjustRow = row } label: { Label("Adjust", systemImage: "pencil") }.tint(Brand.orange)
                        }
                    }
                }
            }
        }
    }
}

struct AddEntrySheet: View {
    let staff: [OwnerStaff]
    var onSave: (String, Date, Date, Date?, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var staffID = ""
    @State private var day = Date()
    @State private var inTime = DubaiDate.date(fromHM: "09:00") ?? Date()
    @State private var hasOut = true
    @State private var outTime = DubaiDate.date(fromHM: "17:00") ?? Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Staff", selection: $staffID) {
                    Text("Select…").tag("")
                    ForEach(staff) { Text($0.name).tag($0.id) }
                }
                DatePicker("Day", selection: $day, displayedComponents: .date)
                DatePicker("Clock in", selection: $inTime, displayedComponents: .hourAndMinute)
                Toggle("Add clock-out", isOn: $hasOut)
                if hasOut { DatePicker("Clock out", selection: $outTime, displayedComponents: .hourAndMinute) }
                TextField("Note (optional)", text: $note)
            }
            .navigationTitle(Text("Add entry", comment: "Add entry title"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(staffID, day, inTime, hasOut ? outTime : nil, note.isEmpty ? nil : note); dismiss()
                    }.disabled(staffID.isEmpty)
                }
            }
        }
    }
}

struct AdjustEntrySheet: View {
    let row: AttendanceRow
    var onSave: (Date, Date, Date) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var day = Date()
    @State private var inTime = Date()
    @State private var outTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                DatePicker("Clock in", selection: $inTime, displayedComponents: .hourAndMinute)
                DatePicker("Clock out", selection: $outTime, displayedComponents: .hourAndMinute)
            }
            .navigationTitle(Text(verbatim: row.name ?? "Entry"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(day, inTime, outTime); dismiss() }
                }
            }
            .onAppear {
                if let ws = row.workDate, let d = DubaiDate.date(fromYMD: ws) { day = d }
                if let ci = DubaiDate.parseISO(row.clockInAt) { inTime = ci }
                if let co = DubaiDate.parseISO(row.clockOutAt) { outTime = co }
            }
        }
    }
}

struct TeamView: View {
    @State private var context = OwnerContext.shared
    @State private var segment = 0
    @State private var rotaVM = RotaViewModel()
    @State private var liveVM = LiveAttendanceViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $segment) {
                Text("Rota").tag(0)
                Text("Live").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if segment == 0 {
                RotaView(vm: rotaVM)
            } else {
                LiveAttendanceView(vm: liveVM)
            }
        }
        .navigationTitle(Text("Team", comment: "Team tab title"))
        .toolbar { VenueSwitcher(context: context) }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID {
                await rotaVM.load(venueID: v)
                await liveVM.load(venueID: v)
            }
        }
    }
}
