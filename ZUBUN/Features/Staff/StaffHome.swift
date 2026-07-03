//
//  StaffHome.swift
//  ZUBUN
//
//  Staff tab shell: Scan (dark) · Clock · Shifts · Me.
//

import SwiftUI

struct StaffHome: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = SessionStore.shared

    var body: some View {
        TabView {
            ScannerView()
                .tabItem { Label("Scan", systemImage: "qrcode.viewfinder") }

            NavigationStack { ClockView() }
                .tabItem { Label("Clock", systemImage: "clock.fill") }

            NavigationStack { ShiftsView() }
                .tabItem { Label("Shifts", systemImage: "calendar") }

            NavigationStack { MeHubView() }
                .tabItem { Label("Me", systemImage: "person.fill") }
        }
        .tint(Brand.orange)
        .task { await PushManager.shared.onActiveSession() }
        // Staff sessions last a shift (12h). If it lapsed while backgrounded,
        // drop to the PIN-only sign-in cleanly (the venue is remembered).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let exp = session.staff?.expiresAt, exp < Date() {
                session.clearStaff()
            }
        }
    }
}
