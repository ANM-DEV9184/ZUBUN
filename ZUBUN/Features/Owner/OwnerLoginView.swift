//
//  OwnerLoginView.swift
//  ZUBUN
//
//  Owner sign in with Supabase email/password (spec §4.3).
//

import SwiftUI
import Observation

@MainActor
@Observable
final class OwnerAuthViewModel {
    var email = ""
    var password = ""
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
}

struct OwnerLoginView: View {
    @State private var vm = OwnerAuthViewModel()
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

                CardContainer {
                    VStack(spacing: 12) {
                        TextField("Email", text: $vm.email)
                            .zKeyboard(.email).zNoAutocap().autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                            .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                        SecureField("Password", text: $vm.password)
                            .environment(\.layoutDirection, .leftToRight)
                            .padding(12).background(Brand.stone, in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                if let error = vm.error { InlineBanner(kind: .error, message: error) }

                PrimaryButton(title: String(localized: "owner.signin", defaultValue: "Sign in"),
                              isLoading: vm.isLoading) {
                    Task { await vm.signIn(onSuccess: onAuthenticated) }
                }
                .disabled(vm.email.isEmpty || vm.password.isEmpty)
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
    }
}
