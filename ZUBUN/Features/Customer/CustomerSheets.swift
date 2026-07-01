//
//  CustomerSheets.swift
//  ZUBUN
//
//  Feedback (1–5★), birthday capture, and an in-app Safari sheet for the Google
//  review link (spec §4.3 / A5 / A7).
//

import SwiftUI
#if os(iOS)
import SafariServices
#endif

/// Allow `URL` to drive `.sheet(item:)`.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct FeedbackSheet: View {
    /// (score 1–5, comment)
    var onSubmit: (Int, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var score = 5
    @State private var comment = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= score ? "star.fill" : "star")
                            .font(.title)
                            .foregroundStyle(Brand.amber)
                            .onTapGesture { score = i }
                            .accessibilityLabel("\(i) stars")
                    }
                }
                TextField("Tell us more (optional)", text: $comment, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                PrimaryButton(title: String(localized: "feedback.submit", defaultValue: "Submit")) {
                    onSubmit(score, comment); dismiss()
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle(Text("Feedback", comment: "Feedback sheet title"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct BirthdaySheet: View {
    var onSave: (Int, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("Birthday", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                PrimaryButton(title: String(localized: "birthday.save", defaultValue: "Save")) {
                    let comps = DubaiDate.calendar.dateComponents([.month, .day], from: date)
                    onSave(comps.month ?? 1, comps.day ?? 1)
                    dismiss()
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle(Text("Your birthday", comment: "Birthday sheet title"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

#if os(iOS)
struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#else
struct SafariSheet: View {
    let url: URL
    var body: some View { Link("Open review", destination: url).padding() }
}
#endif
