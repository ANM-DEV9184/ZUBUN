//
//  StoreManager.swift
//  ZUBUN
//
//  StoreKit 2 owner subscriptions (spec §6/§9.4). The purchase carries
//  `appAccountToken = merchant_id` so the backend's App Store Server Notifications
//  endpoint can reconcile the subscription to the merchant's plan_tier. The app
//  never sets the plan itself — it just purchases and finishes the transaction.
//
//  ⚠️ Requires the In-App Purchase capability + the three auto-renewable products
//  configured in App Store Connect (see AppConfig.iapProductIDs). Until then,
//  `products` is empty and the UI shows an "unavailable" state.
//

import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class StoreManager {
    static let shared = StoreManager()

    var products: [Product] = []
    var isLoading = false
    var message: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = listenForTransactions()
    }

    func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            let items = try await Product.products(for: AppConfig.iapProductIDs)
            products = items.sorted { $0.price < $1.price }
        } catch {
            message = error.localizedDescription
        }
    }

    func purchase(_ product: Product, merchantID: String) async {
        guard let token = UUID(uuidString: merchantID) else {
            message = String(localized: "billing.no_merchant", defaultValue: "Missing merchant id."); return
        }
        do {
            let result = try await product.purchase(options: [.appAccountToken(token)])
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                    message = String(localized: "billing.done", defaultValue: "Purchase complete — your plan updates shortly.")
                } else {
                    message = String(localized: "billing.unverified", defaultValue: "Could not verify the purchase.")
                }
            case .userCancelled:
                break
            case .pending:
                message = String(localized: "billing.pending", defaultValue: "Purchase is pending approval.")
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            message = String(localized: "billing.restored", defaultValue: "Purchases restored.")
        } catch {
            message = error.localizedDescription
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await update in Transaction.updates {
                if case .verified(let txn) = update {
                    await txn.finish()
                }
            }
        }
    }
}
