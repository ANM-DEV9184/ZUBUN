//
//  StaffHome.swift
//  ZUBUN
//
//  Staff tab shell: Scan (dark) · Clock · Shifts · Me.
//

import SwiftUI

struct StaffHome: View {
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
    }
}
