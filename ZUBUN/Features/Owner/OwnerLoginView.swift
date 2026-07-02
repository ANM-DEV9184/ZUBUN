//
//  OwnerLoginView.swift
//  ZUBUN
//
//  Owner sign in — email/password (spec §4.3) or email code (OTP). Admins have
//  no password, so they use the code path; it stores the same owner token and
//  RootRouter sends an admin token to the Super-Admin console.
//

import SwiftUI
import Observation

enum OwnerLoginMode: String, CaseIterable, Identifiable {
    case password, code
    var id: String { rawValue }
    var label: String {
        switch self {
        case .password: return String(localized: "owner.mode.password", defaultValue: "Password")
        case .code:     return String(localized: "owner.mode.code", defaultValue: "Email code")
        }
    }
}

@MainActor
@Observable
final class OwnerAuthViewModel {
    var email = ""
    var password = ""
    var code = ""
    var codeSent = false
    var isLoading = false
    var error: String?
    private let service = OwnerService()

    func signIn(onSuccess: () -> Void) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            try await service.signIn(email: email, password: password)
            onSuccess()
        } catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }

    func sendCode() async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { try await service.sendLoginCode(email: email); codeSent = true }
        catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }

    func verifyCode(onSuccess: () -> Void) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            try await service.signInWithCode(email: email, code: code)
            onSuccess()
        } catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }
}

struct OwnerLoginView: View {
    @State private var vm = OwnerAuthViewModel()
    @State private var mode: OwnerLoginMode = .password
    var onAuthenticated: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "chart.bar.xaxis").font(.system(size: 44)).foregroundStyle(Brand.orange)
                    Text("Owner sign in", comment: "Owner login title").font(.brandTitle())
                    Text("Manage your venue, members and staff.", comment: "Owner login subtitle")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                if !AppConfig.isAnonKeyConfigured {
                    InlineBanner(kind: .warning,
                                 message: String(localized: "config.anon_missing",
                                                 defaultValue: "App not fully configured: Supabase anon key is missing."))
                }

                Picker("Sign-in method", selection: $mode) {
                    ForEach(OwnerLoginMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, _ in vm.error = nil; vm.codeSent = false; vm.code = "" }

                CardContainer {
                    VStack(spacing: 12) {
                        TextField("Email", text: $vm.email)
                            .zKeyboard(.email).zNoAutocap().autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                            .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))

                        if mode == .password {
                            SecureField("Password", text: $vm.password)
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        } else if vm.codeSent {
                            TextField("6-digit code", text: $vm.code)
                                .zKeyboard(.number)
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                if let error = vm.error { InlineBanner(kind: .error, message: error) }

                switch mode {
                case .password:
                    PrimaryButton(title: String(localized: "owner.signin", defaultValue: "Sign in"),
                                  isLoading: vm.isLoading) {
                        Task { await vm.signIn(onSuccess: onAuthenticated) }
                    }
                    .disabled(vm.email.isEmpty || vm.password.isEmpty)

                case .code:
                    if vm.codeSent {
                        PrimaryButton(title: String(localized: "owner.verify", defaultValue: "Verify & sign in"),
                                      isLoading: vm.isLoading) {
                            Task { await vm.verifyCode(onSuccess: onAuthenticated) }
                        }
                        .disabled(vm.code.count < 4)
                        Button(String(localized: "owner.resend", defaultValue: "Send a new code")) {
                            Task { await vm.sendCode() }
                        }
                        .font(.subheadline)
                    } else {
                        PrimaryButton(title: String(localized: "owner.sendcode", defaultValue: "Email me a code"),
                                      isLoading: vm.isLoading) {
                            Task { await vm.sendCode() }
                        }
                        .disabled(vm.email.isEmpty)
                    }
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
    }
}
