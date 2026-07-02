//
//  ClockView.swift
//  ZUBUN
//
//  Clock in/out + break with the 20-min counter code and a selfie (spec B8–B10).
//  On a successful clock punch we capture the buddy-punch selfie and upload it.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ClockViewModel {
    var code = ""
    var isLoading = false
    var banner: (kind: InlineBanner.Kind, text: String)?
    var stats: ShiftStats?

    /// When set, the view presents the selfie camera for this punch ("in"/"out").
    var pendingSelfie: String?
    var showAccessRequest = false
    /// Tracked locally — shift-stats has no "am I clocked in" field; result codes drive it.
    var isClockedIn = false

    private let service = StaffService()

    var codeValid: Bool { code.count == 6 && code.allSatisfy(\.isNumber) }

    func load() async {
        stats = try? await service.shiftStats()
    }

    func clockIn() async {
        await punch({ try await service.clockIn(code: code) }, selfie: "in")
    }

    /// Clock-out needs no code — the mandatory selfie is the presence proof.
    /// Warns (never blocks) if leaving before the scheduled shift end.
    func clockOut() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await service.clockOut()
            switch res.result {
            case .clockedOut:
                isClockedIn = false
                code = ""
                pendingSelfie = "out"   // required — capture the clock-out selfie
                if let early = res.earlyLeaveMinutes, early > 0 {
                    banner = (.warning, "Clocked out \(early) min before your shift ends — this is logged for your manager.")
                } else {
                    banner = (.info, res.result.userMessage)
                }
                await load()
            case .notClockedIn:
                isClockedIn = false
                banner = (.warning, res.result.userMessage)
            default:
                banner = (.error, res.result.userMessage)
            }
        } catch let APIError.result(c) {
            banner = (.error, c.userMessage)
        } catch {
            banner = (.error, error.localizedDescription)
        }
    }

    func startBreak() async { await simpleBreak("start") }
    func stopBreak() async { await simpleBreak("stop") }

    func uploadSelfie(_ jpeg: Data?) async {
        guard let which = pendingSelfie else { return }
        pendingSelfie = nil
        guard let jpeg else { return } // user cancelled — punch already recorded
        _ = try? await service.clockPhoto(which: which, jpeg: jpeg)
    }

    private func punch(_ work: () async throws -> ClockResult, selfie which: String) async {
        guard codeValid else {
            banner = (.warning, ResultCode.badCode.userMessage); return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let res = try await work()
            switch res.result {
            case .clockedIn:
                isClockedIn = true
                banner = (.info, res.result.userMessage)
                pendingSelfie = which
                code = ""
                await load()
            case .clockedOut:
                isClockedIn = false
                banner = (.info, res.result.userMessage)
                pendingSelfie = which
                code = ""
                await load()
            case .alreadyClockedIn:
                isClockedIn = true
                banner = (.warning, res.result.userMessage)
            case .notClockedIn:
                isClockedIn = false
                banner = (.warning, res.result.userMessage)
            case .outsideShift:
                banner = (.warning, res.result.userMessage)
                showAccessRequest = true
            default:
                banner = (.error, res.result.userMessage)
            }
        } catch let APIError.result(c) {
            banner = (.error, c.userMessage)
        } catch {
            banner = (.error, error.localizedDescription)
        }
    }

    private func simpleBreak(_ action: String) async {
        guard codeValid else { banner = (.warning, ResultCode.badCode.userMessage); return }
        isLoading = true; defer { isLoading = false }
        do {
            let res = try await service.breakAction(action, code: code)
            banner = (.info, res.result.userMessage)
        } catch { banner = (.error, error.localizedDescription) }
    }
}

struct ClockView: View {
    @State private var vm = ClockViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                statusCard

                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Counter code", comment: "Clock code field label")
                            .font(.subheadline.weight(.semibold))
                        TextField("000000", text: $vm.code)
                            .zKeyboard(.number)
                            .font(.brandMono())
                            .environment(\.layoutDirection, .leftToRight)
                            .padding()
                            .background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                if let banner = vm.banner {
                    InlineBanner(kind: banner.kind, message: banner.text)
                }

                if vm.isClockedIn {
                    PrimaryButton(title: String(localized: "clock.out", defaultValue: "Clock out"),
                                  systemImage: "stop.circle.fill", isLoading: vm.isLoading, tint: Brand.danger) {
                        Task { await vm.clockOut() }
                    }
                    HStack {
                        Button("Start break") { Task { await vm.startBreak() } }
                            .buttonStyle(.bordered)
                        Button("End break") { Task { await vm.stopBreak() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    PrimaryButton(title: String(localized: "clock.in", defaultValue: "Clock in"),
                                  systemImage: "play.circle.fill", isLoading: vm.isLoading) {
                        Task { await vm.clockIn() }
                    }
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text("Clock", comment: "Clock tab title"))
        .task { await vm.load() }
        .sheet(item: Binding(get: { vm.pendingSelfie.map { SelfieRequest(which: $0) } },
                             set: { if $0 == nil { vm.pendingSelfie = nil } })) { _ in
            SelfieCamera { data in Task { await vm.uploadSelfie(data) } }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $vm.showAccessRequest) {
            AccessRequestSheet().presentationDetents([.medium])
        }
    }

    private var statusCard: some View {
        CardContainer {
            HStack(spacing: 14) {
                Image(systemName: vm.isClockedIn ? "clock.badge.checkmark.fill" : "clock")
                    .font(.system(size: 32))
                    .foregroundStyle(vm.isClockedIn ? Brand.success : Brand.stone500)
                VStack(alignment: .leading, spacing: 4) {
                    Text(vm.isClockedIn ? String(localized: "clock.on_shift", defaultValue: "On shift")
                                        : String(localized: "clock.off_shift", defaultValue: "Not clocked in"))
                        .font(.brandHeadline())
                    if let t = vm.stats?.today {
                        Text("\(t) stamps given today").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }
}

private struct SelfieRequest: Identifiable { let which: String; var id: String { which } }
