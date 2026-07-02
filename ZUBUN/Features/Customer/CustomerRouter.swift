//
//  CustomerRouter.swift
//  ZUBUN
//
//  Cross-cutting navigation state for the customer experience: which tab is
//  showing, the Cards navigation path, a pending venue deep-link (from a push
//  tap), and the inbox unread count for the tab badge. A push that deep-links to
//  a specific venue routes here → Cards tab → that venue's card.
//

import Foundation
import Observation

enum CustomerTab: Hashable {
    case cards, join, inbox, settings
}

@MainActor
@Observable
final class CustomerRouter {
    static let shared = CustomerRouter()
    private init() {}

    /// Selected customer tab (bound to the TabView).
    var tab: CustomerTab = .cards
    /// NavigationStack path for the Cards tab (membership ids).
    var cardPath: [String] = []
    /// A venue we've been asked to open but haven't resolved to a card yet.
    var pendingVenueID: String?
    /// Unread inbox count for the tab badge.
    var unread: Int = 0

    private let service = CustomerService()

    /// Route to a venue's card (from a push tap / deep link). If cards aren't
    /// loaded yet, MyCardsView resolves it once they are.
    func openVenue(venueID: String) {
        guard !venueID.isEmpty else { return }
        pendingVenueID = venueID
        tab = .cards
    }

    func openInbox() { tab = .inbox }

    /// Resolve a pending venue deep-link against the loaded wallet.
    func resolvePending(using cards: [CustomerCard]) {
        guard let vid = pendingVenueID,
              let card = cards.first(where: { $0.venueId == vid }) else { return }
        pendingVenueID = nil
        if cardPath.last != card.membershipId {
            cardPath.append(card.membershipId)
        }
    }

    /// Refresh the unread badge (cheap; called on session start + push tap).
    func refreshUnread() async {
        if let res = try? await service.notifications() { unread = res.unread }
    }

    /// Parse a `zubun://venue/<id>` deep link into a venue id.
    static func venueID(fromDeepLink link: String) -> String? {
        guard let url = URL(string: link), url.host == "venue" else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty || id == "/" ? nil : id
    }
}
