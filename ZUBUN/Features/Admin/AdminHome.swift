//
//  AdminHome.swift
//  ZUBUN
//
//  Super-Admin console shell (role=admin). Dashboard · Merchants · Support · Audit.
//  Full system control lives on the web too; this is the on-the-go console.
//

import SwiftUI
import Observation

struct AdminHome: View {
    var body: some View {
        TabView {
            NavigationStack { AdminDashboardView() }
                .tabItem { Label("Dashboard", systemImage: "speedometer") }
            NavigationStack { AdminMerchantsView() }
                .tabItem { Label("Merchants", systemImage: "building.2.fill") }
            NavigationStack { AdminSupportInboxView() }
                .tabItem { Label("Support", systemImage: "bubble.left.and.bubble.right.fill") }
            NavigationStack { AdminToolsView() }
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver.fill") }
            NavigationStack { AdminAuditView() }
                .tabItem { Label("Audit", systemImage: "list.bullet.rectangle.fill") }
        }
        .tint(Brand.orange)
    }
}

// MARK: - Dashboard

@MainActor
@Observable
final class AdminDashboardViewModel {
    var overview: AdminOverview?
    var isLoading = false
    var error: String?
    private let service = AdminService()

    func load() async {
        isLoading = true; defer { isLoading = false }
        do { overview = try await service.overview(); error = nil }
        catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }
}

struct AdminDashboardView: View {
    @State private var vm = AdminDashboardViewModel()
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = vm.error { InlineBanner(kind: .warning, message: error) }

                LazyVGrid(columns: columns, spacing: 12) {
                    KPITile(title: "Merchants", value: vm.overview?.merchants)
                    KPITile(title: "Venues", value: vm.overview?.venues)
                    KPITile(title: "Members", value: vm.overview?.members)
                    KPITile(title: "Active cards", value: vm.overview?.activeCards)
                    KPITile(title: "Stamps · 7d", value: vm.overview?.stamps7d)
                    KPITile(title: "Open tickets", value: vm.overview?.openTickets)
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text("Admin", comment: "Admin dashboard title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Sign out") { Task { await OwnerService().signOut(); OwnerContext.shared.reset() } }
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }
}

// MARK: - Audit

@MainActor
@Observable
final class AdminAuditViewModel {
    var actions: [AdminAudit] = []
    var isLoading = false
    private let service = AdminService()
    func load() async {
        isLoading = true; defer { isLoading = false }
        actions = (try? await service.audit()) ?? []
    }
}

struct AdminAuditView: View {
    @State private var vm = AdminAuditViewModel()
    var body: some View {
        List {
            if vm.actions.isEmpty && !vm.isLoading {
                Text("No admin actions logged yet.").foregroundStyle(.secondary)
            }
            ForEach(vm.actions) { a in
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.action ?? "—").font(.subheadline.weight(.semibold))
                    Text("\(a.actor ?? "—") → \(a.target ?? "—")").font(.caption).foregroundStyle(.secondary)
                    if let d = DubaiDate.parseISO(a.createdAt) {
                        Text("\(DubaiDate.shortDate(d)) \(DubaiDate.time(d))").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle(Text("Audit log", comment: "Audit title"))
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }
}
