//
//  CustomerLoginView.swift
//  ZUBUN
//
//  Email-OTP sign in (spec §4.1, revised). Step 1: enter email -> send 6-digit
//  code. Step 2: enter code -> verify -> session. (Phone/SMS auth was dropped in
//  favour of free email OTP; mobile is captured as a reference field at join.)
//

import SwiftUI
import Observation

@MainActor
@Observable
final class CustomerAuthViewModel {
    enum Step { case email, code }
    var step: Step = .email
    var email = ""
    var code = ""
    var isLoading = false
    var error: String?

    private let service = CustomerService()

    var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces).lowercased() }
    var emailValid: Bool { Validation.isValidEmail(trimmedEmail) }

    func sendCode() async {
        guard emailValid else {
            error = String(localized: "email.invalid", defaultValue: "Enter a valid email address")
            return
        }
        await run {
            try await service.sendOTP(email: trimmedEmail)
            step = .code
        }
    }

    func verify(onSuccess: () -> Void) async {
        guard code.count >= 4 else { error = String(localized: "otp.short", defaultValue: "Enter the code"); return }
        await run { try await service.verifyOTP(email: trimmedEmail, code: code) }
        if SessionStore.shared.hasCustomerSession { onSuccess() }
    }

    private func run(_ work: () async throws -> Void) async {
        isLoading = true; error = nil
        defer { isLoading = false }
        do { try await work() }
        catch let e as APIError { error = e.errorDescription }
        catch { self.error = error.localizedDescription }
    }
}

struct CustomerLoginView: View {
    @State private var vm = CustomerAuthViewModel()
    var onAuthenticated: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "wallet.pass.fill").font(.system(size: 44)).foregroundStyle(Brand.orange)
                    Text("Your loyalty wallet", comment: "Customer login title").font(.brandTitle())
                    Text("Sign in with your email to see all your cards.", comment: "Customer login subtitle")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                if !AppConfig.isAnonKeyConfigured {
                    InlineBanner(kind: .warning,
                                 message: String(localized: "config.anon_missing",
                                                 defaultValue: "App not fully configured: Supabase anon key is missing."))
                }

                CardContainer {
                    if vm.step == .email {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Email", comment: "Email label").font(.subheadline.weight(.semibold))
                            TextField("you@example.com", text: $vm.email)
                                .zKeyboard(.email).zNoAutocap().autocorrectionDisabled()
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Enter the code sent to \(vm.trimmedEmail)", comment: "OTP label")
                                .font(.subheadline.weight(.semibold))
                            TextField("123456", text: $vm.code)
                                .zKeyboard(.number)
                                .font(.brandMono())
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                if let error = vm.error { InlineBanner(kind: .error, message: error) }

                if vm.step == .email {
                    PrimaryButton(title: String(localized: "otp.send", defaultValue: "Send code"),
                                  isLoading: vm.isLoading) { Task { await vm.sendCode() } }
                        .disabled(!vm.emailValid)
                } else {
                    PrimaryButton(title: String(localized: "otp.verify", defaultValue: "Verify & sign in"),
                                  isLoading: vm.isLoading) { Task { await vm.verify(onSuccess: onAuthenticated) } }
                    Button("Use a different email") { vm.step = .email; vm.code = "" }
                        .font(.subheadline)
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
    }
}
