//
//  StaffLoginView.swift
//  ZUBUN
//
//  PIN login (spec B2). Pick/scan a venue, enter a 4–8 digit PIN. device_mismatch
//  routes to "ask owner to reset device".
//

import SwiftUI

struct StaffLoginView: View {
    @State private var vm = StaffAuthViewModel()
    @State private var showVenueScanner = false
    @State private var showOnboard = false
    var onAuthenticated: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if vm.hasRememberedVenue {
                    // Returning staff on a device already bound to a venue → PIN only.
                    CardContainer {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("PIN", comment: "PIN field label").font(.subheadline.weight(.semibold))
                            SecureField("4–8 digits", text: $vm.pin)
                                .zKeyboard(.number)
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    errorBanner
                    PrimaryButton(title: String(localized: "login.signin", defaultValue: "Sign in"),
                                  systemImage: "lock.open.fill", isLoading: vm.isLoading) {
                        Task { await vm.login(); if SessionStore.shared.staff != nil { onAuthenticated() } }
                    }
                    .disabled(!vm.canSubmitLogin)
                    Button(String(localized: "login.different_venue", defaultValue: "Use a different venue")) {
                        vm.useDifferentVenue()
                    }
                    .font(.subheadline)
                } else {
                    // First time → the invite is the primary path (no venue ID needed).
                    PrimaryButton(title: String(localized: "login.setup_invite", defaultValue: "Set up with your invite"),
                                  systemImage: "person.badge.plus") {
                        showOnboard = true
                    }
                    Text("Your manager sent you a personal invite link — tap above and paste it to set your PIN.",
                         comment: "First-time staff hint")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    DisclosureGroup(String(localized: "login.have_venue", defaultValue: "I already have a venue ID")) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                TextField("Venue ID", text: $vm.venueID)
                                    .zNoAutocap().autocorrectionDisabled()
                                    .environment(\.layoutDirection, .leftToRight)
                                Button { showVenueScanner = true } label: {
                                    Image(systemName: "qrcode.viewfinder").font(.title3)
                                }
                                .accessibilityLabel("Scan venue QR")
                            }
                            .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                            SecureField("4–8 digit PIN", text: $vm.pin)
                                .zKeyboard(.number)
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                            errorBanner
                            PrimaryButton(title: String(localized: "login.signin", defaultValue: "Sign in"),
                                          systemImage: "lock.open.fill", isLoading: vm.isLoading) {
                                Task { await vm.login(); if SessionStore.shared.staff != nil { onAuthenticated() } }
                            }
                            .disabled(!vm.canSubmitLogin)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
        .sheet(isPresented: $showVenueScanner) {
            VenueScanSheet { code in
                vm.setVenueFromScan(code)
                showVenueScanner = false
            }
        }
        .sheet(isPresented: $showOnboard) {
            StaffOnboardView(onDone: { showOnboard = false; onAuthenticated() })
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let error = vm.errorMessage {
            InlineBanner(kind: .error, message: error)
            if error == ResultCode.deviceMismatch.userMessage {
                InlineBanner(kind: .info,
                             message: String(localized: "login.device_reset_hint",
                                             defaultValue: "Ask your owner to reset your device, then log in again."))
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(Brand.orange)
            Text("Staff sign in", comment: "Staff login title").font(.brandTitle())
            if let name = vm.rememberedName {
                Text("Welcome back, \(name). Enter your PIN.", comment: "Returning staff subtitle")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Text("Use your invite the first time, then just your PIN.", comment: "Staff login subtitle")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.top, 24)
    }
}

/// First-time staff onboarding: paste the invite link/token, set a PIN twice
/// (spec B1). Binds the device on success.
struct StaffOnboardView: View {
    @State private var vm = StaffAuthViewModel()
    @State private var invite = ""
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// Accepts a full `/staff/onboard/<token>` link or a bare token.
    private var token: String {
        let trimmed = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: "/staff/onboard/") {
            let tail = trimmed[range.upperBound...]
            return tail.split(separator: "/").first.map(String.init)?
                .split(separator: "?").first.map(String.init) ?? String(tail)
        }
        return trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "onboard.invite", defaultValue: "Invite")) {
                    TextField("Paste your invite link or code", text: $invite, axis: .vertical)
                        .zNoAutocap().autocorrectionDisabled()
                        .environment(\.layoutDirection, .leftToRight)
                }
                Section(String(localized: "onboard.pin", defaultValue: "Choose a PIN")) {
                    SecureField("PIN (4–8 digits)", text: $vm.pin).zKeyboard(.number)
                    SecureField("Confirm PIN", text: $vm.confirmPin).zKeyboard(.number)
                }
                if let error = vm.errorMessage {
                    Section { InlineBanner(kind: .error, message: error) }
                }
                Section {
                    Button {
                        Task { await vm.onboard(token: token); if SessionStore.shared.staff != nil { onDone() } }
                    } label: {
                        HStack { if vm.isLoading { ProgressView() }; Text("Set up & sign in") }
                    }
                    .disabled(token.isEmpty || vm.isLoading)
                }
            }
            .navigationTitle(Text("Staff setup", comment: "Onboard title"))
            .zInlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Lightweight scanner sheet used to fill the venue id from a join QR.
struct VenueScanSheet: View {
    var onScan: (ScannedCode) -> Void
    @State private var authorized = false
    @State private var handled = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if authorized {
                CameraScannerView(onScan: { raw in
                    guard !handled else { return }
                    handled = true
                    onScan(QRParser.parse(raw))
                }, torchOn: false)
                .ignoresSafeArea()
            } else {
                EmptyStateView(systemImage: "camera.fill",
                               title: String(localized: "camera.denied", defaultValue: "Camera access needed"))
                    .foregroundStyle(.white)
            }
            VStack {
                Spacer()
                Text("Point at the venue's join QR", comment: "Venue scan hint")
                    .foregroundStyle(.white)
                    .padding().background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 40)
            }
        }
        .task { authorized = await CameraPermission.ensureAccess() }
    }
}
