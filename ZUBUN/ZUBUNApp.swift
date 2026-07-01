//
//  ZUBUNApp.swift
//  ZUBUN
//
//  App entry. Routes to the right role experience via RootRouter.
//

import SwiftUI

@main
struct ZUBUNApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootRouter()
        }
    }
}
