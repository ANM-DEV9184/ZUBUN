//
//  ManagersView.swift
//  ZUBUN
//
//  Owner → Managers (RBAC v1, Standard/Multi). Invite a manager (they get a
//  restricted Owner experience), list, and remove. Owner-only screen.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class ManagersViewModel {
    var managers: [Manager] = []
    var isLoading = false
    var banner: (InlineBanner.Kind, String)?
    var lastInvite: ManagerInviteResult?
    private let service = OwnerService()

    func load() async {
        isLoading = true; defer { isLoading = false }
        managers = (try? await service.managers()) ?? []
    }

    func invite(_ email: String) async {
        do {
            lastInvite = try await service.inviteManager(email: email)
            banner = (.info, String(localized: "managers.invited", defaultValue: "Manager added."))
            await load()
        } catch let e as APIError {
            banner = (.error, e.errorDescription ?? "Couldn't add manager")
        } catch {
            banner = (.error, error.localizedDescription)
        }
    }

    func remove(_ m: Manager) async {
        try? await service.removeManager(authUserID: m.authUserId)
        await load()
    }
}

struct ManagersView: View {
    @State private var vm = ManagersViewModel()
    @State private var showInvite = false

    var body: some View {
        List {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            if let inv = vm.lastInvite, let pw = inv.tempPassword {
                Section(String(localized: "managers.new", defaultValue: "New manager sign-in")) {
                    LabeledContent("Email", value: inv.email ?? "")
                    LabeledContent("Temp password", value: pw)
                    Text(inv.emailed == true
                         ? String(localized: "managers.emailed", defaultValue: "Emailed to them. They open the app → Owner → sign in, then change the password.")
                         : String(localized: "managers.share", defaultValue: "Share these — the invite email wasn't sent (SMTP not set)."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button { showInvite = true } label: { Label("Invite manager", systemImage: "person.badge.plus") }
            } footer: {
                Text("Managers can run day-to-day operations (approvals, rota, attendance, payroll, campaigns, members) but can't change your plan, venues, or settings.",
                     comment: "Managers footer")
            }

            Section(String(localized: "managers.list", defaultValue: "Managers")) {
                if vm.managers.isEmpty && !vm.isLoading {
                    Text("No managers yet.").foregroundStyle(.secondary)
                }
                ForEach(vm.managers) { m in
                    HStack {
                        Text(m.email)
                        Spacer()
                        Button(role: .destructive) { Task { await vm.remove(m) } } label: {
                            Text("Remove")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle(Text("Managers", comment: "Managers title"))
        .task { await vm.load() }
        .sheet(isPresented: $showInvite) {
            InviteManagerSheet { email in Task { await vm.invite(email) } }
        }
    }
}

private struct InviteManagerSheet: View {
    var onInvite: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Manager's email", text: $email)
                    .zKeyboard(.email).zNoAutocap().autocorrectionDisabled()
                    .environment(\.layoutDirection, .leftToRight)
            }
            .navigationTitle(Text("Invite manager", comment: "Invite manager title")).zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Invite") { onInvite(email.trimmingCharacters(in: .whitespaces)); dismiss() }
                        .disabled(!Validation.isValidEmail(email.trimmingCharacters(in: .whitespaces)))
                }
            }
        }
    }
}
