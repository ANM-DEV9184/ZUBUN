//
//  StaffPerformanceView.swift
//  ZUBUN
//
//  Owner → Staff performance (gap ①). Per-staff issuance (stamps + manual %) and
//  attendance (worked, approved OT, late, no-shows, days) over a chosen date
//  range. Backed by owner_staff_performance.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class StaffPerformanceViewModel {
    var rows: [StaffPerformance] = []
    var isLoading = false
    var error: String?
    var from = Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
    var to = Date()
    private let service = OwnerService()

    func load(venueID: String) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            rows = try await service.staffPerformance(venueID: venueID,
                                                      from: DubaiDate.ymdString(from),
                                                      to: DubaiDate.ymdString(to))
        } catch let e as APIError {
            error = e.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func hours(_ minutes: Int?) -> String {
        let m = minutes ?? 0
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}

struct StaffPerformanceView: View {
    @State private var context = OwnerContext.shared
    @State private var vm = StaffPerformanceViewModel()

    var body: some View {
        List {
            Section {
                DatePicker("From", selection: $vm.from, in: ...vm.to, displayedComponents: .date)
                DatePicker("To", selection: $vm.to, in: vm.from...Date(), displayedComponents: .date)
            }

            if let error = vm.error {
                Section { InlineBanner(kind: .error, message: error) }
            }

            if vm.rows.isEmpty && !vm.isLoading {
                Section { Text("No staff data for this range.").foregroundStyle(.secondary) }
            }

            ForEach(vm.rows) { r in
                Section(r.displayName) {
                    LabeledContent("Stamps issued", value: "\(r.stamps ?? 0)")
                    LabeledContent("Manual %", value: "\(r.manualShare ?? 0)%")
                    LabeledContent("Worked", value: StaffPerformanceViewModel.hours(r.workedMinutes))
                    if (r.overtimeMinutes ?? 0) > 0 {
                        LabeledContent("Approved OT", value: StaffPerformanceViewModel.hours(r.overtimeMinutes))
                    }
                    if (r.lateMinutes ?? 0) > 0 {
                        LabeledContent("Late", value: StaffPerformanceViewModel.hours(r.lateMinutes))
                    }
                    if (r.noShows ?? 0) > 0 {
                        LabeledContent("No-shows", value: "\(r.noShows ?? 0)")
                            .foregroundStyle(Brand.warning)
                    }
                    LabeledContent("Days worked", value: "\(r.daysWorked ?? 0)")
                }
            }
        }
        .navigationTitle(Text("Staff performance", comment: "Staff performance title"))
        .toolbar { VenueSwitcher(context: context) }
        .overlay { if vm.isLoading && vm.rows.isEmpty { LoadingState() } }
        .task(id: reloadKey) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.load(venueID: v) }
        }
    }

    /// Reload when venue or either date changes.
    private var reloadKey: String {
        "\(context.selectedVenueID ?? "")|\(DubaiDate.ymdString(vm.from))|\(DubaiDate.ymdString(vm.to))"
    }
}
