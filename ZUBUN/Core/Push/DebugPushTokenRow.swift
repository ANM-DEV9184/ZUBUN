//
//  DebugPushTokenRow.swift
//  ZUBUN
//
//  DEBUG-only helper: shows + copies the APNs device token so you can paste it
//  into Apple's Push Notifications Console to send a test push. Compiled out of
//  Release builds entirely.
//

#if DEBUG
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct DebugPushTokenRow: View {
    @State private var token = PushManager.shared.deviceToken
    @State private var copied = false

    var body: some View {
        Section("Debug · Push token") {
            if let token {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = token
                    #endif
                    copied = true
                } label: {
                    Label(copied ? "Copied!" : "Copy push token", systemImage: "doc.on.doc")
                }
                Text(token)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("No token yet — run on a real device and allow notifications.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task {
            // The token arrives shortly after registration — poll briefly.
            for _ in 0..<15 where token == nil {
                try? await Task.sleep(for: .seconds(1))
                token = PushManager.shared.deviceToken
            }
        }
    }
}
#endif
