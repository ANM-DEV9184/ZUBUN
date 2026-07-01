//
//  RotaView.swift
//  ZUBUN
//
//  Owner → Rota (spec C6): weekly rota with a day selector, per-staff shift
//  editing (working / off / clear), "copy last week", and the live 20-min clock
//  code. Rota rows are plain `staff_shifts` CRUD under RLS.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class RotaViewModel {
    var staff: [OwnerStaff] = []
    var shifts: [ShiftCell] = []
    var weekStart: Date = DubaiDate.weekStart(Date())
    var selectedDate: Date = DubaiDate.weekStart(Date())
    var clockCode = "----"
    var isLoading = false
    var error: String?

    private var venueID: String?
    private let service = OwnerService()

    var weekDays: [Date] { (0..<7).map { DubaiDate.addDays($0, to: weekStart) } }
    private var weekEnd: Date { DubaiDate.addDays(6, to: weekStart) }

    func load(venueID: String) async {
        self.venueID = venueID
        if selectedDate < weekStart || selectedDate > weekEnd { selectedDate = weekStart }
        isLoading = true; error = nil
        defer { isLoading = false }
        async let st = try? service.venueStaff(venueID: venueID)
        async let sh = try? service.shifts(venueID: venueID,
                                           from: DubaiDate.ymdString(weekStart),
                                           to: DubaiDate.ymdString(weekEnd))
        staff = (await st ?? []).filter { $0.isActive }
        shifts = await sh ?? []
        clockCode = (try? await service.clockCode(venueID: venueID)) ?? "----"
    }

    func reloadShifts() async {
        guard let venueID else { return }
        shifts = (try? await service.shifts(venueID: venueID,
                                            from: DubaiDate.ymdString(weekStart),
                                            to: DubaiDate.ymdString(weekEnd))) ?? shifts
    }

    func refreshClockCode() async {
        guard let venueID else { return }
        clockCode = (try? await service.clockCode(venueID: venueID)) ?? clockCode
    }

    func changeWeek(_ delta: Int) async {
        weekStart = DubaiDate.addDays(delta * 7, to: weekStart)
        selectedDate = weekStart
        if let venueID { await load(venueID: venueID) }
    }

    func shift(for staffID: String, on date: Date) -> ShiftCell? {
        let ds = DubaiDate.ymdString(date)
        return shifts.first { $0.staffId == staffID && $0.workDate == ds }
    }

    func setWorking(staffID: String, date: Date, start: String, end: String, breakMinutes: Int) async {
        await mutate { v in try await service.setWorkingShift(venueID: v, staffID: staffID, date: DubaiDate.ymdString(date), start: start, end: end, breakMinutes: breakMinutes) }
    }
    func setOff(staffID: String, date: Date, leaveType: String) async {
        await mutate { v in try await service.setOffDay(venueID: v, staffID: staffID, date: DubaiDate.ymdString(date), leaveType: leaveType) }
    }
    func clear(staffID: String, date: Date) async {
        await mutate { _ in try await service.clearDay(staffID: staffID, date: DubaiDate.ymdString(date)) }
    }
    func copyLastWeek() async {
        await mutate { v in
            try await service.copyLastWeek(venueID: v,
                                           currentWeekStart: DubaiDate.ymdString(weekStart),
                                           prevWeekStart: DubaiDate.ymdString(DubaiDate.addDays(-7, to: weekStart)),
                                           prevWeekEnd: DubaiDate.ymdString(DubaiDate.addDays(-1, to: weekStart)))
        }
    }

    private func mutate(_ work: (String) async throws -> Void) async {
        guard let venueID else { return }
        do { try await work(venueID); await reloadShifts() }
        catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }
}

struct RotaView: View {
    @Bindable var vm: RotaViewModel
    @State private var editing: EditTarget?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ClockCodeCard(code: vm.clockCode) { Task { await vm.refreshClockCode() } }

                HStack {
                    Button { Task { await vm.changeWeek(-1) } } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text("Week of \(DubaiDate.shortDate(vm.weekStart))").font(.headline)
                    Spacer()
                    Button { Task { await vm.changeWeek(1) } } label: { Image(systemName: "chevron.right") }
                }

                weekStrip

                Button {
                    Task { await vm.copyLastWeek() }
                } label: {
                    Label("Copy last week", systemImage: "doc.on.doc").font(.subheadline)
                }
                .buttonStyle(.bordered)

                if let error = vm.error { InlineBanner(kind: .error, message: error) }

                LazyVStack(spacing: 8) {
                    ForEach(vm.staff) { s in
                        let cell = vm.shift(for: s.id, on: vm.selectedDate)
                        Button { editing = EditTarget(staff: s, cell: cell) } label: {
                            HStack {
                                Text(s.name).font(.headline)
                                Spacer()
                                Text(cell?.timeLabel ?? "—")
                                    .font(.subheadline)
                                    .foregroundStyle(cell?.off == true ? Brand.stone500 : Brand.orange)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    if vm.staff.isEmpty && !vm.isLoading {
                        EmptyStateView(systemImage: "person.2", title: String(localized: "rota.no_staff", defaultValue: "No active staff"))
                    }
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
        .sheet(item: $editing) { target in
            ShiftEditSheet(staffName: target.staff.name, existing: target.cell) { action in
                Task {
                    switch action {
                    case let .working(start, end, brk): await vm.setWorking(staffID: target.staff.id, date: vm.selectedDate, start: start, end: end, breakMinutes: brk)
                    case let .off(type): await vm.setOff(staffID: target.staff.id, date: vm.selectedDate, leaveType: type)
                    case .clear: await vm.clear(staffID: target.staff.id, date: vm.selectedDate)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(vm.weekDays, id: \.self) { day in
                let isSel = DubaiDate.ymdString(day) == DubaiDate.ymdString(vm.selectedDate)
                Button { vm.selectedDate = day } label: {
                    Text(DubaiDate.weekdayShort(day))
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(isSel ? Brand.orange : Color.card, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(isSel ? .white : Brand.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    struct EditTarget: Identifiable {
        let staff: OwnerStaff
        let cell: ShiftCell?
        var id: String { staff.id }
    }
}

struct ClockCodeCard: View {
    let code: String
    var onRefresh: () -> Void
    var body: some View {
        CardContainer {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Counter code", comment: "Clock code label").font(.subheadline).foregroundStyle(.secondary)
                    Text(code).font(.brandMono()).foregroundStyle(Brand.ink)
                }
                Spacer()
                Button(action: onRefresh) { Image(systemName: "arrow.clockwise").font(.title3) }
            }
        }
    }
}

enum ShiftEditAction { case working(start: String, end: String, brk: Int); case off(type: String); case clear }

struct ShiftEditSheet: View {
    let staffName: String
    let existing: ShiftCell?
    var onSave: (ShiftEditAction) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mode = 0 // 0 working, 1 off
    @State private var start = DubaiDate.date(fromHM: "09:00") ?? Date()
    @State private var end = DubaiDate.date(fromHM: "17:00") ?? Date()
    @State private var breakMinutes = 30
    @State private var leaveType = "weekly_off"

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $mode) {
                    Text("Working").tag(0)
                    Text("Off / leave").tag(1)
                }
                .pickerStyle(.segmented)

                if mode == 0 {
                    DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                    Stepper("Unpaid break: \(breakMinutes) min", value: $breakMinutes, in: 0...180, step: 15)
                } else {
                    Picker("Kind", selection: $leaveType) {
                        Text("Weekly off").tag("weekly_off")
                        Text("Annual").tag("annual")
                        Text("Sick").tag("sick")
                        Text("Unpaid").tag("unpaid")
                    }
                }

                Section {
                    Button("Save") {
                        if mode == 0 {
                            onSave(.working(start: DubaiDate.hmString(start), end: DubaiDate.hmString(end), brk: breakMinutes))
                        } else {
                            onSave(.off(type: leaveType))
                        }
                        dismiss()
                    }
                    if existing != nil {
                        Button("Clear day", role: .destructive) { onSave(.clear); dismiss() }
                    }
                }
            }
            .navigationTitle(Text(verbatim: staffName))
            .zInlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let c = existing, !c.off {
                    if let s = DubaiDate.date(fromHM: c.startTime ?? "") { start = s }
                    if let e = DubaiDate.date(fromHM: c.endTime ?? "") { end = e }
                    breakMinutes = c.unpaidBreakMinutes ?? 30
                } else if let c = existing, c.off {
                    mode = 1
                    leaveType = c.leaveType ?? "weekly_off"
                }
            }
        }
    }
}
