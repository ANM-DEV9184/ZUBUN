//
//  SupportCenterView.swift
//  ZUBUN
//
//  Shared in-app Help & Support for every role (Customer / Staff / Owner). The
//  AuthMode passed at init picks the caller's credential; the server routes the
//  ticket to the admin inbox. Create (title + body + photo), chat, status, CSAT.
//

import SwiftUI
import Observation
import PhotosUI

// MARK: - List

@MainActor
@Observable
final class SupportCenterViewModel {
    var tickets: [AppTicket] = []
    var isLoading = false
    var error: String?
    private let service: SupportService
    init(auth: AuthMode) { service = SupportService(auth: auth) }

    func load() async {
        isLoading = true; defer { isLoading = false }
        do { tickets = try await service.tickets(); error = nil }
        catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }
}

struct SupportCenterView: View {
    let auth: AuthMode
    @State private var vm: SupportCenterViewModel
    @State private var showCompose = false

    init(auth: AuthMode) {
        self.auth = auth
        _vm = State(initialValue: SupportCenterViewModel(auth: auth))
    }

    var body: some View {
        List {
            if let error = vm.error { Section { InlineBanner(kind: .warning, message: error) } }

            if vm.tickets.isEmpty && !vm.isLoading {
                Section {
                    Text("No conversations yet. Tap + to reach our support team.",
                         comment: "Empty support state")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(vm.tickets) { t in
                NavigationLink {
                    SupportThreadScreen(auth: auth, ticketID: t.id, subjectFallback: t.subject ?? "Ticket")
                } label: {
                    HStack(spacing: 10) {
                        if t.unread == true {
                            Circle().fill(Brand.orange).frame(width: 8, height: 8)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.subject ?? "Untitled").font(.headline).lineLimit(1)
                            Text(t.lastMessagePreview ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(t.statusLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(t.isClosed ? Brand.stone500 : Brand.success)
                    }
                }
            }
        }
        .navigationTitle(Text("Help & support", comment: "Support center title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCompose = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showCompose) {
            NewTicketSheet(auth: auth) { Task { await vm.load() } }
        }
    }
}

// MARK: - Compose

struct NewTicketSheet: View {
    let auth: AuthMode
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var category: TicketCategory = .other
    @State private var message = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var sending = false
    @State private var banner: (InlineBanner.Kind, String)?

    private var canSend: Bool {
        !subject.trimmingCharacters(in: .whitespaces).isEmpty &&
        !message.trimmingCharacters(in: .whitespaces).isEmpty && !sending
    }

    var body: some View {
        NavigationStack {
            Form {
                if let banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }
                Section {
                    TextField("Subject", text: $subject)
                    Picker("Topic", selection: $category) {
                        ForEach(TicketCategory.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    TextEditor(text: $message).frame(minHeight: 120)
                } header: {
                    Text("Describe your issue", comment: "Ticket body header")
                }
                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? "Attach a photo (optional)" : "Photo attached ✓",
                              systemImage: "paperclip")
                    }
                    if let photoData, let ui = UIImage(data: photoData) {
                        Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                } footer: {
                    Text("Add a screenshot or photo as proof if it helps.", comment: "Attach help")
                }
            }
            .navigationTitle(Text("New ticket", comment: "New ticket title"))
            .zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }.disabled(!canSend)
                }
            }
            .onChange(of: photoItem) { _, item in
                Task { photoData = try? await item?.loadTransferable(type: Data.self) }
            }
        }
    }

    private func send() async {
        sending = true; defer { sending = false }
        let image = photoData.flatMap { SupportImage.dataURL(from: $0) }
        do {
            _ = try await SupportService(auth: auth).create(
                subject: subject.trimmingCharacters(in: .whitespaces),
                body: message.trimmingCharacters(in: .whitespaces),
                category: category.rawValue, imageDataURL: image)
            onCreated(); dismiss()
        } catch let e as APIError { banner = (.error, e.errorDescription ?? "Couldn't send") }
        catch { banner = (.error, error.localizedDescription) }
    }
}

// MARK: - Thread

@MainActor
@Observable
final class SupportThreadViewModel {
    var messages: [AppTicketMessage] = []
    var meta: AppTicketMeta?
    var isLoading = false
    var banner: (InlineBanner.Kind, String)?
    private let service: SupportService
    let ticketID: String
    init(auth: AuthMode, ticketID: String) { service = SupportService(auth: auth); self.ticketID = ticketID }

    func load() async {
        isLoading = true; defer { isLoading = false }
        do { let r = try await service.thread(ticketID: ticketID); meta = r.ticket; messages = r.messages }
        catch let e as APIError { banner = (.error, e.errorDescription ?? "Couldn't load") }
        catch { banner = (.error, error.localizedDescription) }
    }

    func reply(body: String, imageDataURL: String?) async {
        do { try await service.reply(ticketID: ticketID, body: body, imageDataURL: imageDataURL); await load() }
        catch let e as APIError { banner = (.error, e.errorDescription ?? "Couldn't send") }
        catch { banner = (.error, error.localizedDescription) }
    }

    func rate(_ rating: Int, comment: String?) async {
        do { try await service.rate(ticketID: ticketID, rating: rating, comment: comment); await load() }
        catch { banner = (.error, "Couldn't submit rating") }
    }
}

struct SupportThreadScreen: View {
    let auth: AuthMode
    let subjectFallback: String
    @State private var vm: SupportThreadViewModel
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var sending = false

    init(auth: AuthMode, ticketID: String, subjectFallback: String) {
        self.auth = auth
        self.subjectFallback = subjectFallback
        _vm = State(initialValue: SupportThreadViewModel(auth: auth, ticketID: ticketID))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let banner = vm.banner { InlineBanner(kind: banner.0, message: banner.1) }
                    ForEach(vm.messages) { m in MessageBubble(message: m) }

                    if vm.meta?.isResolvedOrClosed == true {
                        CSATCard(alreadyRated: vm.meta?.csatRating) { rating, comment in
                            Task { await vm.rate(rating, comment: comment) }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }

            Divider()
            composer
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text(vm.meta?.subject ?? subjectFallback))
        .zInlineTitle()
        .task { await vm.load() }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let photoData, let ui = UIImage(data: photoData) {
                HStack {
                    Image(uiImage: ui).resizable().scaledToFit().frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button { self.photoData = nil; photoItem = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "paperclip").font(.title3)
                }
                TextField("Message…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                Button {
                    Task { await sendReply() }
                } label: {
                    if sending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                }
                .disabled(sending || (draft.trimmingCharacters(in: .whitespaces).isEmpty && photoData == nil))
                .tint(Brand.orange)
            }
        }
        .padding(12)
        .background(.regularMaterial)
        .onChange(of: photoItem) { _, item in
            Task { photoData = try? await item?.loadTransferable(type: Data.self) }
        }
    }

    private func sendReply() async {
        sending = true; defer { sending = false }
        let image = photoData.flatMap { SupportImage.dataURL(from: $0) }
        let text = draft.trimmingCharacters(in: .whitespaces)
        await vm.reply(body: text, imageDataURL: image)
        draft = ""; photoData = nil; photoItem = nil
    }
}

private struct MessageBubble: View {
    let message: AppTicketMessage
    var body: some View {
        if message.isSystem {
            Text(message.body ?? "")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack {
                if message.isMine { Spacer(minLength: 40) }
                VStack(alignment: .leading, spacing: 6) {
                    if let url = message.imageUrl, let u = URL(string: url) {
                        AsyncImage(url: u) { img in
                            img.resizable().scaledToFit()
                        } placeholder: { ProgressView() }
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if let body = message.body, !body.isEmpty { Text(body) }
                }
                .padding(10)
                .background(message.isMine ? Brand.orange.opacity(0.15) : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12))
                if !message.isMine { Spacer(minLength: 40) }
            }
        }
    }
}

/// Post-resolution feedback. Shows a thank-you if already rated.
private struct CSATCard: View {
    let alreadyRated: Int?
    var onSubmit: (Int, String?) -> Void
    @State private var rating = 0
    @State private var comment = ""

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                if let r = alreadyRated {
                    Label("Thanks for your feedback (\(r)/5)", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Brand.success)
                } else {
                    Text("How did we do?", comment: "CSAT prompt").font(.headline)
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= rating ? "star.fill" : "star")
                                .foregroundStyle(Brand.orange).font(.title3)
                                .onTapGesture { rating = i }
                        }
                    }
                    TextField("Add a comment (optional)", text: $comment, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    Button("Submit feedback") {
                        onSubmit(rating, comment.isEmpty ? nil : comment)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.orange)
                    .disabled(rating == 0)
                }
            }
        }
    }
}
