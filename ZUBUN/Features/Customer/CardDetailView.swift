//
//  CardDetailView.swift
//  ZUBUN
//
//  One loyalty card (spec §4.3). Shows the rotating identity QR (server-minted,
//  never generated locally), reward QR when active, progress, history, and the
//  feedback + birthday prompts.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class CardDetailViewModel {
    let membershipID: String
    var detail: CustomerCardDetail?
    var isLoading = false
    var error: String?
    var banner: String?

    private let service = CustomerService()
    init(membershipID: String) { self.membershipID = membershipID }

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { detail = try await service.card(membershipID: membershipID) }
        catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }

    func submitFeedback(score: Int, comment: String) async -> URL? {
        let res = try? await service.feedback(membershipID: membershipID, score: score,
                                              comment: comment.isEmpty ? nil : comment)
        banner = String(localized: "feedback.thanks", defaultValue: "Thanks for your feedback!")
        if let urlString = res?.reviewUrl { return URL(string: urlString) }
        return nil
    }

    func saveBirthday(month: Int, day: Int) async {
        _ = try? await service.setBirthday(month: month, day: day)
        banner = String(localized: "birthday.saved", defaultValue: "Birthday saved 🎂")
    }

    func optOutThisVenue() async {
        _ = try? await service.optOut(membershipID: membershipID)
        banner = String(localized: "card.opted_out", defaultValue: "You won't get marketing from this venue")
    }
}

struct CardDetailView: View {
    @State private var vm: CardDetailViewModel
    @State private var showFeedback = false
    @State private var showBirthday = false
    @State private var reviewURL: URL?
    @Environment(\.scenePhase) private var scenePhase

    init(membershipID: String) {
        _vm = State(initialValue: CardDetailViewModel(membershipID: membershipID))
    }

    var body: some View {
        ScrollView {
            if let detail = vm.detail {
                VStack(spacing: 18) {
                    progressCard(detail)
                    identityQRCard(detail)
                    if let reward = detail.reward { rewardCard(reward) }
                    if detail.loyaltyMode == .points, let menu = detail.rewardsMenu, !menu.isEmpty {
                        rewardsMenu(menu)
                    }
                    if let history = detail.history, !history.isEmpty { historyCard(history) }
                    actions
                }
                .padding(20)
            } else if vm.isLoading {
                LoadingState().frame(minHeight: 300)
            } else if let error = vm.error {
                InlineBanner(kind: .error, message: error).padding()
            }
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text(verbatim: vm.detail?.venueName ?? "Card"))
        .zInlineTitle()
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await vm.load() } }  // refresh rotating identity QR on return
        }
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet { score, comment in
                Task { reviewURL = await vm.submitFeedback(score: score, comment: comment) }
            }.presentationDetents([.medium])
        }
        .sheet(isPresented: $showBirthday) {
            BirthdaySheet { m, d in Task { await vm.saveBirthday(month: m, day: d) } }
                .presentationDetents([.medium])
        }
        .sheet(item: $reviewURL) { url in SafariSheet(url: url) }
        .overlay(alignment: .bottom) {
            if let banner = vm.banner {
                Text(banner).padding().background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .task { try? await Task.sleep(for: .seconds(2)); vm.banner = nil }
            }
        }
    }

    private func progressCard(_ d: CustomerCardDetail) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(d.venueName).font(.brandHeadline())
                    Spacer()
                    TierBadge(tier: d.tier)
                }
                if d.loyaltyMode == .stamps {
                    StampGrid(count: d.stampsCount, required: d.stampsRequired ?? 0)
                    if let text = d.rewardText {
                        Text(text).font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(d.pointsBalance) points").font(.brandTitle()).foregroundStyle(Brand.orange)
                }
            }
        }
    }

    private func identityQRCard(_ d: CustomerCardDetail) -> some View {
        CardContainer {
            VStack(spacing: 10) {
                Text("Show this to staff", comment: "Identity QR caption").font(.subheadline.weight(.semibold))
                if let image = QRImage.generate(from: d.identityQr) {
                    image.resizable().interpolation(.none).scaledToFit().frame(width: 220, height: 220)
                        .accessibilityLabel(Text("Your loyalty QR code — show to staff to collect a stamp",
                                                  comment: "Identity QR a11y label"))
                } else {
                    EmptyStateView(systemImage: "qrcode", title: "QR unavailable")
                }
                Text("Refreshes daily for your security", comment: "QR rotation note")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func rewardCard(_ reward: ActiveReward) -> some View {
        CardContainer {
            VStack(spacing: 10) {
                Label("Reward ready", systemImage: "gift.fill")
                    .font(.brandHeadline()).foregroundStyle(Brand.success)
                if let text = reward.rewardText { Text(text).font(.subheadline) }
                if let image = QRImage.generate(from: reward.rewardQr) {
                    image.resizable().interpolation(.none).scaledToFit().frame(width: 180, height: 180)
                        .accessibilityLabel(Text("Reward QR code — show to staff to redeem",
                                                  comment: "Reward QR a11y label"))
                }
                Text("Show to staff to redeem", comment: "Reward QR caption")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func rewardsMenu(_ menu: [RewardMenuItem]) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rewards", comment: "Rewards menu title").font(.brandHeadline())
                ForEach(menu) { item in
                    HStack {
                        Text(item.label)
                        Spacer()
                        Text("\(item.pointsCost) pts").foregroundStyle(Brand.orange)
                    }
                }
            }
        }
    }

    private func historyCard(_ history: [String]) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent visits", comment: "History title").font(.brandHeadline())
                ForEach(Array(history.prefix(20).enumerated()), id: \.offset) { _, raw in
                    if let date = DubaiDate.parseISO(raw) {
                        Text(DubaiDate.shortDate(date)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { showFeedback = true } label: {
                Label("Leave feedback", systemImage: "star.fill").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered)
            Button { showBirthday = true } label: {
                Label("Add my birthday", systemImage: "gift").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered)
            Button(role: .destructive) { Task { await vm.optOutThisVenue() } } label: {
                Label("Stop offers from this venue", systemImage: "bell.slash").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered)
        }
    }
}

struct StampGrid: View {
    let count: Int
    let required: Int
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<max(required, 1), id: \.self) { i in
                Circle()
                    .fill(i < count ? Brand.orange : Brand.stone200)
                    .overlay(Image(systemName: "star.fill").font(.caption)
                        .foregroundStyle(i < count ? .white : .clear))
                    .frame(height: 40)
            }
        }
    }
}
