//
//  AdminToolsView.swift
//  ZUBUN
//
//  Admin → Tools: the "something's broken" toolkit — retry dead jobs, replay
//  failed webhooks, and review fraud/anomaly signals. (6A)
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AdminToolsViewModel {
    var jobs: [AdminJob] = []
    var webhooks: [AdminWebhook] = []
    var signals: [AdminSignal] = []
    var banner: (InlineBanner.Kind, String)?
    private let service = AdminService()

    func load() async {
        async let j = service.deadJobs()
        async let w = service.failedWebhooks()
        async let s = service.anomalies()
        jobs = (try? await j) ?? []
        webhooks = (try? await w) ?? []
        signals = (try? await s) ?? []
    }

    func retry(_ job: AdminJob) async {
        do { try await service.retryJob(id: job.id); banner = (.info, "Job requeued."); await load() }
        catch { banner = (.error, "Retry failed") }
    }
    func retryAll() async {
        do { let n = try await service.retryAllJobs(); banner = (.info, "Requeued \(n) job\(n == 1 ? "" : "s")."); await load() }
        catch { banner = (.error, "Retry failed") }
    }
    func replay(_ e: AdminWebhook) async {
        do { try await service.replayWebhook(id: e.id); banner = (.info, "Webhook replayed."); await load() }
        catch { banner = (.error, "Replay failed") }
    }
}

struct AdminToolsView: View {
    @State private var vm = AdminToolsViewModel()

    var body: some View {
        List {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            Section {
                if vm.jobs.isEmpty {
                    Text("No dead jobs 🎉").foregroundStyle(.secondary)
                } else {
                    Button {
                        Task { await vm.retryAll() }
                    } label: { Label("Retry all (\(vm.jobs.count))", systemImage: "arrow.clockwise") }
                    ForEach(vm.jobs) { j in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(j.jobType ?? "job").font(.subheadline.weight(.semibold))
                                Spacer()
                                Button("Retry") { Task { await vm.retry(j) } }
                                    .buttonStyle(.bordered).tint(Brand.orange)
                            }
                            if let e = j.error { Text(e).font(.caption).foregroundStyle(Brand.danger).lineLimit(2) }
                            Text("Attempts: \(j.attempts ?? 0)").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: { Text("Dead jobs") } footer: { Text("Background tasks that failed all retries.") }

            Section {
                if vm.webhooks.isEmpty {
                    Text("No failed webhooks").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.webhooks) { e in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(e.from ?? "unknown").font(.subheadline.weight(.semibold))
                                Spacer()
                                Button("Replay") { Task { await vm.replay(e) } }
                                    .buttonStyle(.bordered).tint(Brand.orange)
                            }
                            if let err = e.error { Text(err).font(.caption).foregroundStyle(Brand.danger).lineLimit(2) }
                        }
                    }
                }
            } header: { Text("Failed webhooks") }

            Section {
                if vm.signals.isEmpty {
                    Text("No anomalies detected").foregroundStyle(.secondary)
                } else {
                    ForEach(vm.signals) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(s.title ?? "—", systemImage: s.kind == "fallback_overuse" ? "hand.raised.fill" : "person.fill.questionmark")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Brand.warning)
                            Text(s.detail ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("Anomalies · last 7 days") } footer: {
                Text("Staff stamping far above their venue's median, or heavy manual-fallback use.")
            }
        }
        .navigationTitle(Text("Tools", comment: "Admin tools title"))
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }
}
