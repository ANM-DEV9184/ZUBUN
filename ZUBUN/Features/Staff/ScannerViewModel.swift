//
//  ScannerViewModel.swift
//  ZUBUN
//
//  Drives the staff scanner (spec B4/B5/B6/B7). Parses dayem:c:/dayem:r:, relays
//  to the backend, maps results to an overlay, debounces repeat reads, and falls
//  back to the offline queue when the network is down.
//

import Foundation
import Observation
#if canImport(UIKit)
import UIKit
#endif

struct ScanOutcome: Identifiable, Equatable {
    let id = UUID()
    let tone: ResultTone
    let title: String
    let detail: String?
    let progress: String?   // e.g. "3 / 8"
    var capOverride: Bool = false   // daily cap hit → offer "request owner approval"
}

@MainActor
@Observable
final class ScannerViewModel {
    var torchOn = false
    var isProcessing = false
    var outcome: ScanOutcome?
    var showPhonePad = false
    var lastCustomerQR: String?     // enables "+ bonus" after a stamp
    var bannerMessage: String?

    private let service = StaffService()
    private let offline = OfflineQueue.shared
    private var lastScan: (code: String, at: Date)?

    /// Called by the camera with each decoded string.
    func handleScan(_ raw: String) {
        let now = Date()
        // Debounce: ignore the same code within 3s (the camera fires continuously).
        if let last = lastScan, last.code == raw, now.timeIntervalSince(last.at) < 3 { return }
        lastScan = (raw, now)
        guard !isProcessing else { return }

        switch QRParser.parse(raw) {
        case .customer(let qr):
            Task { await stamp(qr: qr) }
        case .reward(let qr):
            Task { await redeem(qr: qr) }
        case .joinVenue, .staffOnboard, .unknown:
            present(.init(tone: .error,
                          title: String(localized: "scan.unknown", defaultValue: "Not a ZUBUN code"),
                          detail: nil, progress: nil))
        }
    }

    func stamp(qr: String) async {
        await process {
            let res = try await service.stamp(qr: qr)
            lastCustomerQR = qr
            return outcome(for: res)
        } onOffline: {
            offline.enqueueStamp(qr: qr)
            return .init(tone: .info,
                         title: String(localized: "scan.queued", defaultValue: "Saved offline"),
                         detail: String(localized: "scan.queued.detail", defaultValue: "Will sync when you're back online."),
                         progress: nil)
        }
    }

    func redeem(qr: String) async {
        await process {
            let res = try await service.redeem(qr: qr)
            let tone = res.result.tone
            return .init(tone: tone, title: res.result.userMessage,
                         detail: res.rewardLabel, progress: nil)
        } onOffline: {
            // Redemptions are single-use; safer not to blind-queue. Surface the state.
            return .init(tone: .info,
                         title: String(localized: "scan.offline", defaultValue: "You're offline"),
                         detail: String(localized: "scan.offline.redeem", defaultValue: "Reconnect to redeem rewards."),
                         progress: nil)
        }
    }

    func bonus(count: Int) async {
        guard let qr = lastCustomerQR else { return }
        await process {
            let res = try await service.bonus(qr: qr, count: count)
            return outcome(for: res)
        } onOffline: {
            offline.enqueue(PendingOp(id: UUID(), kind: .bonus, qr: qr, count: count, createdAt: Date()))
            return .init(tone: .info,
                         title: String(localized: "scan.queued", defaultValue: "Saved offline"),
                         detail: nil, progress: nil)
        }
    }

    func phoneFallback(_ phone: String) async {
        let normalized = Validation.normalizeUAEPhone(phone)
        guard Validation.isValidE164(normalized) else {
            bannerMessage = ResultCode.invalidPhone.userMessage
            return
        }
        showPhonePad = false
        await process {
            let res = try await service.stampFallback(phone: normalized)
            return outcome(for: res)
        } onOffline: {
            return .init(tone: .info,
                         title: String(localized: "scan.offline", defaultValue: "You're offline"),
                         detail: String(localized: "scan.offline.fallback", defaultValue: "Reconnect to use phone entry."),
                         progress: nil)
        }
    }

    // MARK: - Helpers

    private func outcome(for res: StampResult) -> ScanOutcome {
        let progress: String?
        if let c = res.stampsCount, let r = res.stampsRequired {
            progress = "\(c) / \(r)"
        } else if let p = res.pointsBalance {
            progress = "\(p) pts"
        } else {
            progress = nil
        }
        var title = res.result.userMessage
        if let name = res.customerName, res.result == .stamped || res.result == .rewardIssued {
            title = "\(res.result.userMessage) · \(name)"
        }
        return .init(tone: res.result.tone, title: title, detail: res.rewardText, progress: progress,
                     capOverride: res.result == .dailyCapReached)
    }

    /// Ask the owner/manager to approve one extra stamp after the daily cap.
    func requestOverride() async {
        guard let qr = lastCustomerQR else { return }
        await process {
            let result = try await service.requestCapOverride(qr: qr)
            let ok = result == "requested" || result == "already_pending"
            return .init(
                tone: ok ? .info : .error,
                title: ok ? String(localized: "scan.override.sent", defaultValue: "Sent to owner for approval")
                          : String(localized: "scan.override.fail", defaultValue: "Couldn't request approval"),
                detail: result == "already_pending"
                    ? String(localized: "scan.override.pending", defaultValue: "Already waiting for approval") : nil,
                progress: nil)
        } onOffline: {
            return .init(tone: .info,
                         title: String(localized: "scan.offline", defaultValue: "You're offline"),
                         detail: nil, progress: nil)
        }
    }

    private func process(_ work: () async throws -> ScanOutcome,
                         onOffline: () -> ScanOutcome) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let outcome = try await work()
            present(outcome)
        } catch APIError.offline {
            present(onOffline())
        } catch APIError.rateLimited {
            present(.init(tone: .warning,
                          title: String(localized: "scan.rate_limited", defaultValue: "Slow down a moment"),
                          detail: nil, progress: nil))
        } catch let APIError.result(code) {
            present(.init(tone: code.tone, title: code.userMessage, detail: nil, progress: nil))
        } catch {
            present(.init(tone: .error, title: error.localizedDescription, detail: nil, progress: nil))
        }
    }

    private func present(_ outcome: ScanOutcome) {
        self.outcome = outcome
        #if canImport(UIKit)
        let style: UINotificationFeedbackGenerator.FeedbackType =
            outcome.tone == .error ? .error : (outcome.tone == .warning ? .warning : .success)
        UINotificationFeedbackGenerator().notificationOccurred(style)
        #endif
    }
}
