//
//  JoinVenueView.swift
//  ZUBUN
//
//  Join a venue from the app (spec §4.1). Scan the venue join QR (or paste a
//  venue id), confirm name + marketing consent -> adds a card to the wallet.
//

import SwiftUI
import Observation

struct JoinVenueView: View {
    @State private var venueID = ""
    @State private var name = ""
    @State private var marketingOptIn = true
    @State private var showScanner = false
    @State private var banner: (InlineBanner.Kind, String)?
    @State private var loading = false
    private let service = CustomerService()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        Button { showScanner = true } label: {
                            Label("Scan venue QR", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Brand.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Brand.ink)
                        }
                        TextField("…or paste a venue ID", text: $venueID)
                            .zNoAutocap().autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                            .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        TextField("Your name (optional)", text: $name)
                            .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        Toggle("Receive offers on WhatsApp", isOn: $marketingOptIn)
                    }
                }

                if let banner { InlineBanner(kind: banner.0, message: banner.1) }

                PrimaryButton(title: String(localized: "join.submit", defaultValue: "Join venue"),
                              isLoading: loading) { Task { await join() } }
                    .disabled(!QRParser.isUUID(venueID.trimmingCharacters(in: .whitespaces)))
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text("Join a venue", comment: "Join title"))
        .sheet(isPresented: $showScanner) {
            VenueScanSheet { code in
                if case let .joinVenue(id) = code { venueID = id }
                showScanner = false
            }
        }
    }

    private func join() async {
        loading = true; defer { loading = false }
        do {
            let res = try await service.join(venueID: venueID.trimmingCharacters(in: .whitespaces),
                                             name: name.isEmpty ? nil : name,
                                             marketingOptIn: marketingOptIn)
            switch res.result {
            case .enrolled, .alreadyMember:
                banner = (.info, res.result.userMessage)
            default:
                banner = (.warning, res.result.userMessage)
            }
        } catch let e as APIError {
            banner = (.error, e.errorDescription ?? "Error")
        } catch {
            banner = (.error, error.localizedDescription)
        }
    }
}
