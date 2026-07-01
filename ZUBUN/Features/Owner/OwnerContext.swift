//
//  OwnerContext.swift
//  ZUBUN
//
//  Shared owner session context: the venue list + currently-selected venue that
//  the Members and Approvals tabs operate on. Loaded once per sign-in.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class OwnerContext {
    static let shared = OwnerContext()

    var venues: [OwnerVenue] = []
    var selectedVenueID: String?
    var isLoaded = false

    private let service = OwnerService()
    private init() {}

    var selectedVenue: OwnerVenue? { venues.first { $0.id == selectedVenueID } }

    func loadVenues() async {
        guard !isLoaded else { return }
        if let v = try? await service.venues() {
            venues = v
            if selectedVenueID == nil || !v.contains(where: { $0.id == selectedVenueID }) {
                selectedVenueID = v.first?.id
            }
            isLoaded = true
        }
    }

    func reset() {
        venues = []
        selectedVenueID = nil
        isLoaded = false
    }
}

/// A toolbar venue picker shared by the Members / Approvals tabs.
struct VenueSwitcher: ToolbarContent {
    @Bindable var context: OwnerContext

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if context.venues.count > 1 {
                Menu {
                    Picker("Venue", selection: $context.selectedVenueID) {
                        ForEach(context.venues) { venue in
                            Text(venue.isPaused ? "\(venue.name) (paused)" : venue.name).tag(venue.id as String?)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(context.selectedVenue?.name ?? "Venue").font(.headline)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                }
            } else {
                Text(context.selectedVenue?.name ?? "").font(.headline)
            }
        }
    }
}
