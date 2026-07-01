//
//  BillingView.swift
//  ZUBUN
//
//  Owner → Billing (spec C16): current plan + StoreKit 2 subscription purchase +
//  restore. No external payment links (Apple anti-steering). Plan reconciliation
//  happens server-side via App Store Server Notifications.
//

import SwiftUI
import StoreKit

struct BillingView: View {
    @State private var store = StoreManager.shared
    @State private var plan: MerchantPlan?
    private let service = OwnerService()

    var body: some View {
        List {
            Section("Current plan") {
                LabeledContent("Tier", value: (plan?.planTier ?? "—").capitalized)
                LabeledContent("Status", value: (plan?.billingStatus ?? "—").capitalized)
            }

            if store.isLoading && store.products.isEmpty {
                Section { HStack { ProgressView(); Text("Loading plans…") } }
            } else if store.products.isEmpty {
                Section {
                    Text("No subscriptions available yet. Configure the products in App Store Connect to enable in-app billing.",
                         comment: "IAP unavailable")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Plans") {
                    ForEach(store.products, id: \.id) { product in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(product.displayName).font(.headline)
                                Text(product.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(product.displayPrice) {
                                Task { if let m = service.merchantID { await store.purchase(product, merchantID: m) } }
                            }
                            .buttonStyle(.borderedProminent).tint(Brand.orange)
                        }
                    }
                }
            }

            if let msg = store.message {
                Section { InlineBanner(kind: .info, message: msg) }
            }

            Section {
                Button("Restore purchases") { Task { await store.restore() } }
            } footer: {
                Text("Subscriptions are billed through your Apple ID and renew automatically until cancelled in Settings.",
                     comment: "IAP disclosure")
            }
        }
        .navigationTitle(Text("Billing", comment: "Billing title"))
        .task {
            await store.load()
            plan = try? await service.merchantPlan()
        }
    }
}
