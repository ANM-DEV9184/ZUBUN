//
//  FeedbackView.swift
//  ZUBUN
//
//  Owner → Feedback (NPS). Response count, average score, promoters/detractors,
//  the 1–5 distribution, and the most recent low-score comments to act on.
//

import SwiftUI

struct FeedbackView: View {
    @State private var context = OwnerContext.shared
    @State private var summary: FeedbackSummary?
    @State private var loading = false
    private let service = OwnerService()

    var body: some View {
        List {
            if let s = summary, (s.count ?? 0) > 0 {
                Section(String(localized: "feedback.overview", defaultValue: "Overview")) {
                    LabeledContent("Responses", value: "\(s.count ?? 0)")
                    LabeledContent("Average score", value: s.avg.map { String(format: "%.2f", $0) } ?? "—")
                    LabeledContent("Promoters (4–5)", value: "\(s.promoters ?? 0)")
                    LabeledContent("Detractors (1–2)", value: "\(s.detractors ?? 0)")
                }

                if let dist = s.dist {
                    Section(String(localized: "feedback.distribution", defaultValue: "Distribution")) {
                        ForEach(Array(stride(from: 5, through: 1, by: -1)), id: \.self) { star in
                            HStack {
                                Text(String(repeating: "★", count: star)).foregroundStyle(Brand.orange)
                                Spacer()
                                Text("\(dist["\(star)"] ?? 0)").monospacedDigit()
                            }
                        }
                    }
                }

                if let lows = s.recentLow, !lows.isEmpty {
                    Section(String(localized: "feedback.recent_low", defaultValue: "Recent low scores")) {
                        ForEach(lows) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("★ \(c.score ?? 0)").font(.caption.weight(.bold)).foregroundStyle(Brand.warning)
                                if let cm = c.comment, !cm.isEmpty { Text(cm).font(.subheadline) }
                            }
                        }
                    }
                }
            } else if !loading {
                EmptyStateView(systemImage: "star.bubble",
                               title: String(localized: "feedback.empty", defaultValue: "No feedback yet"),
                               message: String(localized: "feedback.empty.detail", defaultValue: "Ratings customers leave after a reward will show up here."))
            }
        }
        .navigationTitle(Text("Feedback", comment: "Feedback title"))
        .toolbar { VenueSwitcher(context: context) }
        .overlay { if loading && summary == nil { LoadingState() } }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await load(v) }
        }
    }

    private func load(_ venueID: String) async {
        loading = true; defer { loading = false }
        summary = try? await service.feedbackSummary(venueID: venueID)
    }
}
