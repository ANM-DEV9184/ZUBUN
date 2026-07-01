//
//  SupportView.swift
//  ZUBUN
//
//  Owner → Support (spec C18): ticket list + thread + reply + CSAT. RLS table
//  ops with the owner JWT (the Next.js support routes are cookie-only). Text-only
//  (attachments require a server-signed URL); 20s poll refresh, no realtime yet.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class SupportViewModel {
    var tickets: [SupportTicket] = []
    var isLoading = false
    var error: String?
    private let service = OwnerService()

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { tickets = try await service.supportTickets() }
        catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }

    func create(subject: String, category: String, body: String) async {
        try? await service.createTicket(subject: subject, category: category, body: body)
        await load()
    }
}

struct SupportView: View {
    @State private var vm = SupportViewModel()
    @State private var showNew = false

    var body: some View {
        List {
            if let error = vm.error { InlineBanner(kind: .error, message: error) }
            ForEach(vm.tickets) { t in
                NavigationLink { SupportThreadView(ticket: t) { Task { await vm.load() } } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.subject ?? "Support").font(.headline)
                            Text(t.lastMessagePreview ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text((t.status ?? "").capitalized).font(.caption2).foregroundStyle(.secondary)
                            if t.unread { Circle().fill(Brand.orange).frame(width: 8, height: 8) }
                        }
                    }
                }
            }
            if vm.tickets.isEmpty && !vm.isLoading {
                EmptyStateView(systemImage: "bubble.left.and.bubble.right",
                               title: String(localized: "support.empty", defaultValue: "No conversations"))
                    .listRowSeparator(.hidden)
            }
        }
        .navigationTitle(Text("Support", comment: "Support title"))
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { showNew = true } label: { Image(systemName: "square.and.pencil") } } }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .sheet(isPresented: $showNew) {
            NewTicketSheet { subject, category, body in Task { await vm.create(subject: subject, category: category, body: body) } }
        }
    }
}

@MainActor
@Observable
final class SupportThreadViewModel {
    let ticket: SupportTicket
    var messages: [SupportMessage] = []
    var draft = ""
    var showRate = false
    private let service = OwnerService()
    init(ticket: SupportTicket) { self.ticket = ticket }

    func load() async {
        messages = (try? await service.supportMessages(ticketID: ticket.id)) ?? []
        try? await service.markTicketRead(ticketID: ticket.id)
    }
    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        draft = ""
        try? await service.replyToTicket(ticketID: ticket.id, body: body)
        await load()
    }
    func rate(_ stars: Int) async {
        try? await service.rateTicket(ticketID: ticket.id, rating: stars, comment: nil)
        showRate = false
    }
}

struct SupportThreadView: View {
    @State private var vm: SupportThreadViewModel
    var onChange: () -> Void

    init(ticket: SupportTicket, onChange: @escaping () -> Void) {
        _vm = State(initialValue: SupportThreadViewModel(ticket: ticket))
        self.onChange = onChange
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.messages) { m in
                        HStack {
                            if m.isOwner { Spacer(minLength: 40) }
                            Text(m.body ?? "")
                                .padding(10)
                                .background(m.isOwner ? Brand.orange.opacity(0.9) : Color.card,
                                            in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(m.isOwner ? .white : Brand.ink)
                            if !m.isOwner { Spacer(minLength: 40) }
                        }
                    }
                }
                .padding()
            }

            if vm.ticket.isClosed {
                VStack(spacing: 8) {
                    Text("This conversation is resolved.", comment: "Resolved note").font(.caption).foregroundStyle(.secondary)
                    Button("Rate support") { vm.showRate = true }.buttonStyle(.bordered)
                }
                .padding()
            } else {
                HStack {
                    TextField("Message", text: $vm.draft, axis: .vertical)
                        .padding(10).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                    Button { Task { await vm.send(); onChange() } } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
        }
        .navigationTitle(Text(verbatim: vm.ticket.subject ?? "Support"))
        .zInlineTitle()
        .task { await vm.load() }
        .confirmationDialog("Rate support", isPresented: $vm.showRate, titleVisibility: .visible) {
            ForEach(1...5, id: \.self) { n in
                Button("\(n) star\(n > 1 ? "s" : "")") { Task { await vm.rate(n) } }
            }
        }
    }
}

struct NewTicketSheet: View {
    var onCreate: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var subject = ""
    @State private var category = "other"
    @State private var message = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Subject", text: $subject)
                Picker("Category", selection: $category) {
                    Text("Billing").tag("billing"); Text("Technical").tag("technical")
                    Text("How-to").tag("how_to"); Text("Other").tag("other")
                }
                TextField("How can we help?", text: $message, axis: .vertical).lineLimit(4, reservesSpace: true)
            }
            .navigationTitle(Text("New ticket", comment: "New ticket title"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { onCreate(subject, category, message); dismiss() }
                        .disabled(subject.isEmpty || message.isEmpty)
                }
            }
        }
    }
}
