//
//  Reachability.swift
//  ZUBUN
//
//  Proactive network monitor (NWPathMonitor). Drives a global offline banner and
//  triggers the staff offline queue to replay on reconnect.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class Reachability {
    static let shared = Reachability()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "io.zubun.reachability")

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in Reachability.shared.update(online) }
        }
        monitor.start(queue: queue)
    }

    private func update(_ online: Bool) {
        let wasOffline = !isOnline
        isOnline = online
        if online && wasOffline {
            // Came back online — flush any queued staff scans.
            Task { await OfflineQueue.shared.replayAll() }
        }
    }
}
