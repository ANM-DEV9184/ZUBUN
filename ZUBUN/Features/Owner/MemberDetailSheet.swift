//
//  MemberDetailSheet.swift
//  ZUBUN
//
//  Owner member detail (spec C4): stamp history (who stamped), reward history,
//  and grant-stamps action.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class MemberDetailViewModel {
    let member: MemberRow
    var stamps: [MemberStamp] = []
    var rewards: [MemberReward] = []
    var grantCount = 1
    var grantReason = ""
    var banner: (InlineBanner.Kind, String)?
    var isWorking = false

    private let service = OwnerService()
    init(member: MemberRow) { self.member = member }

    func load() async {
        async let s = try? service.memberStamps(membershipID: member.id)
        async let r = try? service.memberRewards(membershipID: member.id)
        stamps = await s ?? []
        rewards = await r ?? []
    }

    func grant() async {
        isWorking = true; defer { isWorking = false }
        do {
            let res = try await service.grantStamps(membershipID: member.id,
                                                    count: grantCount,
                                                    reason: grantReason.isEmpty ? "owner bonus" : grantReason)
            switch res.result {
            case "stamped", "reward_issued":
                banner = (.info, res.result == "reward_issued"
                          ? String(localized: "grant.reward", defaultValue: "Reward issued 🎉")
                          : String(localized: "grant.ok", defaultValue: "Stamps granted"))
                await load()
            default:
                banner = (.warning, ResultCode(rawValue: res.result ?? "")?.userMessage ?? (res.result ?? "Failed"))
            }
        } catch let e as APIError {
            banner = (.error, e.errorDescription ?? "Error")
        } catch {
            banner = (.error, error.localizedDescription)
        }
    }
}

struct MemberDetailSheet: View {
    @State private var vm: MemberDetailViewModel
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(member: MemberRow, onChange: @escaping () -> Void) {
        _vm = State(initialValue: MemberDetailViewModel(member: member))
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Name", value: vm.member.displayName)
                    if let phone = vm.member.customers?.phoneE164 { LabeledContent("Phone", value: phone) }
                    LabeledContent("Stamps", value: "\(vm.member.stampsCount ?? 0)")
                    if let tier = vm.member.tier { LabeledContent("Tier", value: tier.label) }
                    LabeledContent("Marketing", value: (vm.member.marketingOptIn ?? false) ? "Opted in" : "Opted out")
                }

                Section(String(localized: "member.grant", defaultValue: "Grant stamps")) {
                    Stepper("Count: \(vm.grantCount)", value: $vm.grantCount, in: 1...10)
                    TextField("Reason (optional)", text: $vm.grantReason)
                    if let banner = vm.banner { InlineBanner(kind: banner.0, message: banner.1) }
                    Button {
                        Task { await vm.grant(); onChange() }
                    } label: {
                        HStack { if vm.isWorking { ProgressView() }; Text("Grant") }
                    }
                    .disabled(vm.isWorking)
                }

                Section(String(localized: "member.stamps_history", defaultValue: "Recent stamps")) {
                    if vm.stamps.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                    ForEach(vm.stamps) { s in
                        HStack {
                            Text(DubaiDate.parseISO(s.createdAt).map(DubaiDate.shortDate) ?? "—")
                            if s.fallbackFlag == true {
                                Text("manual").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Brand.warning.opacity(0.15), in: Capsule()).foregroundStyle(Brand.warning)
                            }
                            Spacer()
                            Text(s.staffUsers?.displayName ?? "—").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(String(localized: "member.rewards_history", defaultValue: "Rewards")) {
                    if vm.rewards.isEmpty { Text("None yet").foregroundStyle(.secondary) }
                    ForEach(vm.rewards) { r in
                        HStack {
                            Text(r.status?.capitalized ?? "—")
                            Spacer()
                            Text(DubaiDate.parseISO(r.createdAt).map(DubaiDate.shortDate) ?? "")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(Text(verbatim: vm.member.displayName))
            .zInlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await vm.load() }
        }
    }
}
