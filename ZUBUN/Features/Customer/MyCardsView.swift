//
//  MyCardsView.swift
//  ZUBUN
//
//  The multi-venue wallet (spec §4.1). Lists every membership as a card tile with
//  progress, tier and a "reward ready" flag.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class WalletViewModel {
    var cards: [CustomerCard] = []
    var isLoading = false
    var error: String?
    private let service = CustomerService()

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { cards = try await service.cards() }
        catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }
}

struct MyCardsView: View {
    @State private var vm = WalletViewModel()

    var body: some View {
        ScrollView {
            if vm.isLoading && vm.cards.isEmpty {
                LoadingState().frame(minHeight: 300)
            } else if let error = vm.error, vm.cards.isEmpty {
                VStack(spacing: 16) {
                    InlineBanner(kind: .error, message: error)
                    Button("Retry") { Task { await vm.load() } }.buttonStyle(.bordered)
                }.padding()
            } else if vm.cards.isEmpty {
                EmptyStateView(systemImage: "wallet.pass",
                               title: String(localized: "wallet.empty", defaultValue: "No cards yet"),
                               message: String(localized: "wallet.empty.detail", defaultValue: "Join a venue to add your first loyalty card."))
                    .frame(minHeight: 300)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(vm.cards) { card in
                        NavigationLink(value: card.membershipId) {
                            CardTile(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text("My cards", comment: "Wallet title"))
        .navigationDestination(for: String.self) { id in
            CardDetailView(membershipID: id)
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }
}

struct CardTile: View {
    let card: CustomerCard
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(card.venueName).font(.brandHeadline())
                    Spacer()
                    TierBadge(tier: card.tier)
                }
                if card.loyaltyMode == .stamps {
                    ProgressView(value: card.progress)
                        .tint(Brand.orange)
                    Text("\(card.stampsCount) / \(card.stampsRequired ?? 0) stamps")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("\(card.pointsBalance) points")
                        .font(.title3.weight(.bold)).foregroundStyle(Brand.orange)
                }
                if card.rewardReady {
                    Label("Reward ready", systemImage: "gift.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(Brand.success)
                }
                if card.venuePaused {
                    Label("Program paused", systemImage: "pause.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
