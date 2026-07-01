//
//  OfflineQueue.swift
//  ZUBUN
//
//  Persists scan/clock ops made offline; replays oldest-first on reconnect.
//  Backend idempotency (60s stamp key, single-use tokens) makes replay safe
//  (spec §3 / §5.3).
//

import Foundation
import Observation

struct PendingOp: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case stamp, redeem, bonus }
    let id: UUID
    let kind: Kind
    let qr: String
    var count: Int?
    let createdAt: Date
}

@MainActor
@Observable
final class OfflineQueue {
    static let shared = OfflineQueue()

    private let key = "zubun.offline.ops"
    private(set) var ops: [PendingOp] = []
    private let service = StaffService()

    var pendingCount: Int { ops.count }

    private init() { load() }

    func enqueue(_ op: PendingOp) {
        ops.append(op)
        persist()
    }

    func enqueueStamp(qr: String) {
        enqueue(PendingOp(id: UUID(), kind: .stamp, qr: qr, count: nil, createdAt: Date()))
    }

    /// Replays everything oldest-first. Stops on the first transport failure so
    /// ordering is preserved; result codes (duplicate, etc.) are treated as done.
    func replayAll() async {
        guard SessionStore.shared.staff != nil else { return }
        var remaining = ops.sorted { $0.createdAt < $1.createdAt }
        while let op = remaining.first {
            do {
                switch op.kind {
                case .stamp:  _ = try await service.stamp(qr: op.qr)
                case .redeem: _ = try await service.redeem(qr: op.qr)
                case .bonus:  _ = try await service.bonus(qr: op.qr, count: op.count ?? 1)
                }
                remaining.removeFirst()
                ops.removeAll { $0.id == op.id }
                persist()
            } catch APIError.offline {
                break // still offline; keep the rest
            } catch {
                // A typed result (duplicate / errors) means the server saw it — drop it.
                remaining.removeFirst()
                ops.removeAll { $0.id == op.id }
                persist()
            }
        }
    }

    func clear() {
        ops.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder.zubun.encode(ops) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder.zubun.decode([PendingOp].self, from: data) else { return }
        ops = decoded
    }
}
