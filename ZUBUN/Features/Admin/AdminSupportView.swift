//
//  AdminSupportView.swift
//  ZUBUN
//
//  Admin → Support inbox: every role's tickets, with reply, internal note, and
//  status control (resolve/close emails the raiser a transcript server-side).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AdminSupportInboxViewModel {
    var tickets: [AdminTicket] = []
    var showAll = false
    var isLoading = false
    private let service = AdminService()

    func load() async {
        isLoading = true; defer { isLoading = false }
        tickets = (try? await service.tickets(status: showAll ? "all" : "open")) ?? []
    }
}

struct AdminSupportInboxView: View {
    @State private var vm = AdminSupportInboxViewModel()

    var body: some View {
        List {
            Picker("Filter", selection: $vm.showAll) {
                Text("Open").tag(false)
                Text("All").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.showAll) { _, _ in Task { await vm.load() } }

            if vm.tickets.isEmpty && !vm.isLoading {
                Text("No tickets.").foregroundStyle(.secondary)
            }
            ForEach(vm.tickets) { t in
                NavigationLink { AdminTicketThreadView(ticketID: t.id, subjectFallback: t.subject ?? "Ticket") } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            if t.unread == true { Circle().fill(Brand.orange).frame(width: 8, height: 8) }
                            Text(t.subject ?? "—").font(.headline).lineLimit(1)
                            Spacer()
                            if t.awaiting == true {
                                Text("Awaiting").font(.caption2.weight(.bold)).foregroundStyle(Brand.warning)
                            }
                        }
                        Text(t.raiserBadge).font(.caption).foregroundStyle(Brand.orange)
                        Text(t.lastMessagePreview ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text("\((t.status ?? "").capitalized)\(t.csatRating.map { " · ★\($0)" } ?? "")")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle(Text("Support", comment: "Admin support title"))
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }
}

@MainActor
@Observable
final class AdminTicketThreadViewModel {
    var messages: [AppTicketMessage] = []
    var meta: AdminThreadMeta?
    var banner: (InlineBanner.Kind, String)?
    let ticketID: String
    private let service = AdminService()
    init(ticketID: String) { self.ticketID = ticketID }

    func load() async {
        if let r = try? await service.thread(ticketID: ticketID) { meta = r.ticket; messages = r.messages }
    }
    func reply(_ body: String) async {
        do { try await service.reply(ticketID: ticketID, body: body); await load() }
        catch { banner = (.error, "Couldn't send") }
    }
    func note(_ body: String) async {
        do { try await service.note(ticketID: ticketID, body: body); await load() }
        catch { banner = (.error, "Couldn't add note") }
    }
    func setStatus(_ status: String) async {
        do { try await service.setStatus(ticketID: ticketID, status: status); await load() }
        catch { banner = (.error, "Couldn't update status") }
    }
}

struct AdminTicketThreadView: View {
    let subjectFallback: String
    @State private var vm: AdminTicketThreadViewModel
    @State private var draft = ""
    @State private var noteMode = false
    @State private var sending = false

    init(ticketID: String, subjectFallback: String) {
        self.subjectFallback = subjectFallback
        _vm = State(initialValue: AdminTicketThreadViewModel(ticketID: ticketID))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let banner = vm.banner { InlineBanner(kind: banner.0, message: banner.1) }
                    if let m = vm.meta {
                        Text("\((m.raiserKind ?? "user").capitalized) · \(m.raiserLabel ?? "—")")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(vm.messages) { m in AdminBubble(message: m) }
                }
                .padding(16)
            }
            Divider()
            composer
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text(vm.meta?.subject ?? subjectFallback))
        .zInlineTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Mark resolved") { Task { await vm.setStatus("resolved") } }
                    Button("Close ticket") { Task { await vm.setStatus("closed") } }
                    Button("Reopen") { Task { await vm.setStatus("open") } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await vm.load() }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            Toggle(isOn: $noteMode) {
                Label("Internal note (hidden from the customer)", systemImage: "lock.fill").font(.caption)
            }
            .toggleStyle(.switch)
            HStack(spacing: 10) {
                TextField(noteMode ? "Add a private note…" : "Reply…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                Button {
                    Task {
                        sending = true; defer { sending = false }
                        let text = draft.trimmingCharacters(in: .whitespaces)
                        guard !text.isEmpty else { return }
                        if noteMode { await vm.note(text) } else { await vm.reply(text) }
                        draft = ""
                    }
                } label: {
                    if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                }
                .disabled(sending || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .tint(Brand.orange)
            }
        }
        .padding(12)
        .background(.regularMaterial)
    }
}

private struct AdminBubble: View {
    let message: AppTicketMessage
    private var mine: Bool { message.senderRole == "admin" }
    var body: some View {
        if message.senderRole == "system" {
            Text(message.body ?? "").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack {
                if mine { Spacer(minLength: 40) }
                VStack(alignment: .leading, spacing: 6) {
                    if message.senderRole == "note" {
                        Label("Internal note", systemImage: "lock.fill").font(.caption2).foregroundStyle(Brand.warning)
                    }
                    if let url = message.imageUrl, let u = URL(string: url) {
                        AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .frame(maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if let body = message.body, !body.isEmpty { Text(body) }
                }
                .padding(10)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
                if !mine { Spacer(minLength: 40) }
            }
        }
    }
    private var bubbleColor: Color {
        if message.senderRole == "note" { return Brand.warning.opacity(0.15) }
        return mine ? Brand.orange.opacity(0.15) : Color(.secondarySystemBackground)
    }
}
