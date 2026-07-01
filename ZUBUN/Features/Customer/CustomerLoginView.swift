//
//  CustomerLoginView.swift
//  ZUBUN
//
//  Phone-OTP sign in (spec §4.1 / §9.3). Step 1: enter phone -> send OTP.
//  Step 2: enter the 6-digit code -> verify -> session.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class CustomerAuthViewModel {
    enum Step { case phone, code }
    var step: Step = .phone
    var phone = ""
    var code = ""
    var isLoading = false
    var error: String?

    private let service = CustomerService()

    var normalizedPhone: String { Validation.normalizeUAEPhone(phone) }
    var phoneValid: Bool { Validation.isValidE164(normalizedPhone) }

    func sendCode() async {
        guard phoneValid else { error = ResultCode.invalidPhone.userMessage; return }
        await run {
            try await service.sendOTP(phone: normalizedPhone)
            step = .code
        }
    }

    func verify(onSuccess: () -> Void) async {
        guard code.count >= 4 else { error = String(localized: "otp.short", defaultValue: "Enter the code"); return }
        await run { try await service.verifyOTP(phone: normalizedPhone, code: code) }
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
                    Text("Sign in with your phone to see all your cards.", comment: "Customer login subtitle")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                if !AppConfig.isAnonKeyConfigured {
                    InlineBanner(kind: .warning,
                                 message: String(localized: "config.anon_missing",
                                                 defaultValue: "App not fully configured: Supabase anon key is missing."))
                }

                CardContainer {
                    if vm.step == .phone {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Phone number", comment: "Phone label").font(.subheadline.weight(.semibold))
                            TextField("+9715XXXXXXXX", text: $vm.phone)
                                .zKeyboard(.phone)
                                .environment(\.layoutDirection, .leftToRight)
                                .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Enter the code sent to \(vm.normalizedPhone)", comment: "OTP label")
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

                if vm.step == .phone {
                    PrimaryButton(title: String(localized: "otp.send", defaultValue: "Send code"),
                                  isLoading: vm.isLoading) { Task { await vm.sendCode() } }
                        .disabled(!vm.phoneValid)
                } else {
                    PrimaryButton(title: String(localized: "otp.verify", defaultValue: "Verify & sign in"),
                                  isLoading: vm.isLoading) { Task { await vm.verify(onSuccess: onAuthenticated) } }
                    Button("Use a different number") { vm.step = .phone; vm.code = "" }
                        .font(.subheadline)
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
    }
}
