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
    @State private var recent: [OwnerFeedbackItem] = []
    @State private var loading = false
    @State private var replyTarget: OwnerFeedbackItem?
    @State private var replyText = ""
    @State private var banner: (InlineBanner.Kind, String)?
    private let service = OwnerService()

    var body: some View {
        List {
            if let banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }
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

                if !recent.isEmpty {
                    Section(String(localized: "feedback.recent_low", defaultValue: "Recent low scores")) {
                        ForEach(recent) { c in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("★ \(c.score ?? 0)").font(.caption.weight(.bold)).foregroundStyle(Brand.warning)
                                if let cm = c.comment, !cm.isEmpty { Text(cm).font(.subheadline) }
                                if let reply = c.ownerReply, !reply.isEmpty {
                                    Label(reply, systemImage: "arrowshape.turn.up.left.fill")
                                        .font(.caption).foregroundStyle(Brand.success)
                                } else {
                                    Button("Reply") { replyTarget = c; replyText = "" }
                                        .font(.caption.weight(.semibold)).tint(Brand.orange)
                                }
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
        .alert("Reply to feedback", isPresented: Binding(get: { replyTarget != nil }, set: { if !$0 { replyTarget = nil } })) {
            TextField("Your reply", text: $replyText)
            Button("Send") { Task { await sendReply() } }
            Button("Cancel", role: .cancel) { replyTarget = nil }
        } message: {
            Text("The customer gets your reply as a notification.")
        }
    }

    private func load(_ venueID: String) async {
        loading = true; defer { loading = false }
        summary = try? await service.feedbackSummary(venueID: venueID)
        recent = (try? await service.feedbackList(venueID: venueID, onlyLow: true)) ?? []
    }

    private func sendReply() async {
        guard let target = replyTarget else { return }
        let text = replyText.trimmingCharacters(in: .whitespaces)
        replyTarget = nil
        guard !text.isEmpty else { return }
        do {
            try await service.replyFeedback(id: target.id, reply: text)
            if let v = context.selectedVenueID { await load(v) }
        } catch { banner = (.error, "Couldn't send reply") }
    }
}
