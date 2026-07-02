//
//  BillingView.swift
//  ZUBUN
//
//  Owner → Billing: READ-ONLY plan status. Subscriptions are sold and managed on
//  the ZUBUN web dashboard via Stripe (B2B). Per Apple's guidelines this companion
//  app shows plan status only — no in-app purchase UI and no external payment
//  links/CTAs (anti-steering safe).
//

import SwiftUI

struct BillingView: View {
    @State private var plan: MerchantPlan?
    @State private var isLoading = true
    @State private var loadFailed = false
    private let service = OwnerService()

    private var tierLabel: String { (plan?.planTier ?? "—").capitalized }
    private var statusLabel: String { (plan?.billingStatus ?? "—").capitalized }

    var body: some View {
        List {
            if loadFailed && plan == nil {
                Section {
                    InlineBanner(kind: .error, message: String(localized: "billing.load_failed", defaultValue: "Couldn't load your plan."))
                    Button("Retry") { Task { await load() } }
                }
            }

            Section(String(localized: "billing.current_plan", defaultValue: "Current plan")) {
                LabeledContent(String(localized: "billing.plan", defaultValue: "Plan"), value: tierLabel)
                LabeledContent(String(localized: "billing.status", defaultValue: "Status"), value: statusLabel)
            }

            if let plan {
                Section(String(localized: "billing.includes", defaultValue: "Your plan includes")) {
                    ForEach(planFeatures(plan.planTier), id: \.self) { feature in
                        Label(feature, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                    }
                }
            }

            Section {
                Text("Your ZUBUN subscription is managed by your account administrator on the web dashboard.",
                     comment: "Billing management note")
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: {
                Text("Managing your plan", comment: "Billing manage header")
            }
        }
        .navigationTitle(Text("Billing", comment: "Billing title"))
        .overlay { if isLoading && plan == nil { LoadingState() } }
        .task { await load() }
    }

    private func load() async {
        isLoading = true; loadFailed = false
        do {
            plan = try await service.merchantPlan()
            loadFailed = (plan == nil)
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func planFeatures(_ tier: String?) -> [String] {
        switch tier {
        case "multi":
            return ["Up to 3 venues (pooled)", "Campaigns & promotions", "Time & attendance + payroll", "Priority support"]
        case "standard":
            return ["Campaigns & promotions", "Time & attendance + payroll", "Segments & analytics"]
        default:
            return ["Loyalty program", "Time & attendance + payroll", "Segments"]
        }
    }
}
