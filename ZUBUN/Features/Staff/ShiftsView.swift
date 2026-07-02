//
//  ShiftsView.swift
//  ZUBUN
//
//  Staff activity + requests (spec §5.5). The backend exposes no staff
//  shifts/attendance read route, so this surfaces the shift-stats summary
//  (today / 7-day / venue / leaderboard) and the request actions.
//

import SwiftUI

struct ShiftsView: View {
    @State private var stats: ShiftStats?
    @State private var shifts: [StaffShift] = []
    @State private var showRequests = false
    @State private var showAccess = false
    private let service = StaffService()
    private var myName: String? { SessionStore.shared.staff?.displayName }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    StatCard(value: stats?.today, label: String(localized: "stats.today", defaultValue: "My stamps today"))
                    StatCard(value: stats?.my7d, label: String(localized: "stats.7d", defaultValue: "Last 7 days"))
                }
                HStack(spacing: 12) {
                    StatCard(value: stats?.venueToday, label: String(localized: "stats.venue", defaultValue: "Venue today"))
                    StatCard(value: stats?.rank(forName: myName), label: String(localized: "stats.rank", defaultValue: "My rank"))
                }

                if !shifts.isEmpty {
                    CardContainer {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("My schedule", comment: "Staff schedule title").font(.brandHeadline())
                            ForEach(shifts.prefix(10)) { s in
                                HStack {
                                    Text(s.dateLabel)
                                    Spacer()
                                    Text(s.displayTimes)
                                        .foregroundStyle(s.isOff ? Color.secondary : Brand.ink)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }

                if let board = stats?.leaderboard, !board.isEmpty {
                    CardContainer {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Today's leaderboard", comment: "Leaderboard title").font(.brandHeadline())
                            ForEach(Array(board.prefix(5).enumerated()), id: \.offset) { i, row in
                                HStack {
                                    Text("\(i + 1). \(row.name ?? "—")")
                                    Spacer()
                                    Text("\(row.today ?? 0)").foregroundStyle(Brand.orange)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }

                PrimaryButton(title: String(localized: "shifts.request_leave", defaultValue: "Request leave / day-off"),
                              systemImage: "calendar.badge.plus") { showRequests = true }
                Button {
                    showAccess = true
                } label: {
                    Label("Request out-of-hours access", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text("Activity", comment: "Activity tab title"))
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showRequests) { NavigationStack { RequestsView() } }
        .sheet(isPresented: $showAccess) { AccessRequestSheet().presentationDetents([.medium]) }
    }

    private func load() async {
        async let s = service.shiftStats()
        async let sh = service.shifts()
        stats = try? await s
        shifts = (try? await sh) ?? []
    }
}

struct StatCard: View {
    let value: Int?
    let label: String
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text(value.map(String.init) ?? "—").font(.brandTitle()).foregroundStyle(Brand.ink)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
