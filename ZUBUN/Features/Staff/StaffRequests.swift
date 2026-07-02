//
//  StaffRequests.swift
//  ZUBUN
//
//  Out-of-hours/overtime/device-reset, leave, day-off move, shift swap
//  (spec B11/B13/B14/B15). Each posts to the owner approval queue.
//

import SwiftUI
import Observation

struct AccessRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "out_of_hours"
    @State private var reason = ""
    @State private var banner: String?
    @State private var loading = false
    private let service = StaffService()

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    Text("Out of hours").tag("out_of_hours")
                    Text("Overtime").tag("overtime")
                    Text("Device reset").tag("device_reset")
                }
                Section("Reason (optional)") {
                    TextField("Why do you need access?", text: $reason, axis: .vertical)
                }
                if let banner { Text(banner).foregroundStyle(Brand.orange) }
                Button {
                    Task {
                        loading = true; defer { loading = false }
                        let res = try? await service.requestAccess(kind: kind, reason: reason.isEmpty ? nil : reason)
                        banner = (res?.result ?? .invalid).userMessage
                        if res?.result == .requested { dismiss() }
                    }
                } label: {
                    HStack { if loading { ProgressView() }; Text("Send request") }
                }
            }
            .navigationTitle(Text("Request access", comment: "Access request title"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct RequestsView: View {
    @State private var leaveFrom = Date()
    @State private var leaveTo = Date()
    @State private var leaveType = "annual"
    @State private var reason = ""
    @State private var dayoffFrom = Date()
    @State private var dayoffTo = Date()
    @State private var missNote = ""
    // Shift swap
    @State private var myShifts: [StaffShift] = []
    @State private var colleagues: [StaffColleague] = []
    @State private var swapShiftID = ""
    @State private var swapToStaff = ""
    @State private var swapReason = ""
    @State private var banner: (InlineBanner.Kind, String)?
    @State private var loading = false
    private let service = StaffService()

    /// Only real working shifts can be swapped.
    private var workingShifts: [StaffShift] { myShifts.filter { !$0.isOff && $0.startTime != nil } }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.timeZone = DubaiDate.timeZone; f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        Form {
            Section(String(localized: "requests.leave", defaultValue: "Request leave")) {
                Picker("Type", selection: $leaveType) {
                    Text("Annual").tag("annual")
                    Text("Sick").tag("sick")
                    Text("Unpaid").tag("unpaid")
                }
                DatePicker("From", selection: $leaveFrom, displayedComponents: .date)
                DatePicker("To", selection: $leaveTo, displayedComponents: .date)
                TextField("Reason (optional)", text: $reason, axis: .vertical)
                Button("Submit leave request") { Task { await submitLeave() } }
                    .disabled(loading)
            }

            Section(String(localized: "requests.dayoff", defaultValue: "Move a day off")) {
                DatePicker("From (a current day off)", selection: $dayoffFrom, displayedComponents: .date)
                DatePicker("To", selection: $dayoffTo, displayedComponents: .date)
                Button("Request day-off move") { Task { await submitDayoff() } }
                    .disabled(loading)
            }

            Section(String(localized: "requests.missed", defaultValue: "Report a missed clock-in")) {
                TextField("What happened? (optional)", text: $missNote, axis: .vertical)
                Button("Send report") { Task { await submitMissed() } }
                    .disabled(loading)
            }

            if !workingShifts.isEmpty && !colleagues.isEmpty {
                Section(String(localized: "requests.swap", defaultValue: "Swap a shift")) {
                    Picker("My shift", selection: $swapShiftID) {
                        Text("Select…").tag("")
                        ForEach(workingShifts) { s in
                            Text("\(s.dateLabel) · \(s.displayTimes)").tag(s.id)
                        }
                    }
                    Picker("Swap with", selection: $swapToStaff) {
                        Text("Select…").tag("")
                        ForEach(colleagues) { c in Text(c.name).tag(c.id) }
                    }
                    TextField("Reason (optional)", text: $swapReason, axis: .vertical)
                    Button("Request swap") { Task { await submitSwap() } }
                        .disabled(loading || swapShiftID.isEmpty || swapToStaff.isEmpty)
                }
            }

            if let banner {
                Section { InlineBanner(kind: banner.0, message: banner.1) }
            }
        }
        .navigationTitle(Text("Requests", comment: "Requests title"))
        .task {
            async let s = service.shifts()
            async let c = service.colleagues()
            myShifts = (try? await s) ?? []
            colleagues = (try? await c) ?? []
        }
    }

    private func submitSwap() async {
        loading = true; defer { loading = false }
        do {
            let res = try await service.swap(shiftID: swapShiftID, toStaff: swapToStaff,
                                             reason: swapReason.isEmpty ? nil : swapReason)
            banner = (res.result == .requested ? .info : .warning, res.result.userMessage)
            if res.result == .requested { swapShiftID = ""; swapToStaff = ""; swapReason = "" }
        } catch { banner = (.error, error.localizedDescription) }
    }

    private func submitDayoff() async {
        loading = true; defer { loading = false }
        do {
            let res = try await service.requestDayoffChange(
                from: Self.dateFmt.string(from: dayoffFrom),
                to: Self.dateFmt.string(from: dayoffTo),
                reason: nil)
            banner = (res.result == .requested ? .info : .warning, res.result.userMessage)
        } catch { banner = (.error, error.localizedDescription) }
    }

    private func submitMissed() async {
        loading = true; defer { loading = false }
        do {
            let res = try await service.reportMissingClockIn(note: missNote.isEmpty ? nil : missNote)
            banner = (.info, res.result == .unknown ? String(localized: "requests.missed.sent", defaultValue: "Report sent") : res.result.userMessage)
        } catch { banner = (.error, error.localizedDescription) }
    }

    private func submitLeave() async {
        loading = true; defer { loading = false }
        do {
            let res = try await service.requestLeave(
                from: Self.dateFmt.string(from: leaveFrom),
                to: Self.dateFmt.string(from: leaveTo),
                leaveType: leaveType,
                reason: reason.isEmpty ? nil : reason)
            banner = (res.result == .requested ? .info : .warning, res.result.userMessage)
        } catch {
            banner = (.error, error.localizedDescription)
        }
    }
}
