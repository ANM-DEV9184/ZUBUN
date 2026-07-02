//
//  NotificationsView.swift
//  ZUBUN
//
//  The customer's in-app notification inbox (Phase 3). Lists venue-scoped
//  campaign notifications; tapping one marks it read and deep-links to that
//  venue's card. Resilient to OS push being off — the inbox is the source of
//  truth (each push also writes a row server-side).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class InboxViewModel {
    var items: [CustomerNotification] = []
    var isLoading = false
    var error: String?
    private let service = CustomerService()

    func load() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let res = try await service.notifications()
            items = res.notifications
            CustomerRouter.shared.unread = res.unread
        } catch let e as APIError {
            error = e.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markAllRead() async {
        _ = try? await service.markNotificationRead(id: nil)
        markLocallyRead(id: nil)
        CustomerRouter.shared.unread = 0
    }

    /// Optimistically mark read locally (single item or all when id == nil).
    func markLocallyRead(id: String?) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        items = items.map { n in
            guard n.isUnread, id == nil || n.id == id else { return n }
            return n.markedRead(at: stamp)
        }
    }
}

struct NotificationsView: View {
    @State private var vm = InboxViewModel()
    @State private var router = CustomerRouter.shared

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                LoadingState().frame(maxWidth: .infinity, minHeight: 300)
            } else if let error = vm.error, vm.items.isEmpty {
                VStack(spacing: 16) {
                    InlineBanner(kind: .error, message: error)
                    Button("Retry") { Task { await vm.load() } }.buttonStyle(.bordered)
                }.padding()
            } else if vm.items.isEmpty {
                EmptyStateView(systemImage: "bell",
                               title: String(localized: "inbox.empty", defaultValue: "No notifications"),
                               message: String(localized: "inbox.empty.detail", defaultValue: "Updates from venues you've joined will show up here."))
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                List {
                    ForEach(vm.items) { item in
                        Button { open(item) } label: { NotificationRow(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text("Notifications", comment: "Inbox title"))
        .toolbar {
            if vm.items.contains(where: { $0.isUnread }) {
                Button(String(localized: "inbox.markAllRead", defaultValue: "Mark all read")) {
                    Task { await vm.markAllRead() }
                }
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }

    private func open(_ item: CustomerNotification) {
        vm.markLocallyRead(id: item.id)
        router.unread = max(0, router.unread - 1)
        Task { try? await CustomerService().markNotificationRead(id: item.id) }
        if let venueID = item.venueId {
            router.openVenue(venueID: venueID)
        }
    }
}

private struct NotificationRow: View {
    let item: CustomerNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.isUnread ? Brand.orange : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(item.isUnread ? .bold : .semibold))
                Text(item.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(item.relativeTime)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private extension CustomerNotification {
    /// Return a copy with read_at set (optimistic local update).
    func markedRead(at stamp: String) -> CustomerNotification {
        CustomerNotification(id: id, venueId: venueId, membershipId: membershipId,
                             campaignId: campaignId, category: category, title: title,
                             body: body, deepLink: deepLink, readAt: stamp, createdAt: createdAt)
    }

    var relativeTime: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: createdAt)
            ?? ISO8601DateFormatter().date(from: createdAt)
        guard let date else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
