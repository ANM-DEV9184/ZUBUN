//
//  StaffManagementView.swift
//  ZUBUN
//
//  Owner → Staff management (Phase 5): roster, add a staffer (share the
//  onboarding invite link so they set their own PIN), suspend / reactivate.
//  Plus the venue Join-QR generator the customer scans to join.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class StaffMgmtViewModel {
    var staff: [OwnerStaff] = []
    var isLoading = false
    var banner: (InlineBanner.Kind, String)?
    /// Most recent invite link to share/copy after adding a staffer.
    var inviteURL: String?
    private var venueID: String?
    private let service = OwnerService()

    func load(venueID: String) async {
        self.venueID = venueID
        isLoading = true; defer { isLoading = false }
        staff = (try? await service.venueStaff(venueID: venueID)) ?? []
    }

    func add(name: String) async {
        guard let v = venueID, name.count >= 2 else { return }
        do {
            let invite = try await service.addStaff(venueID: v, name: name)
            inviteURL = invite.inviteUrl
            banner = (.info, String(localized: "staff.added", defaultValue: "Added — share the invite so they can set a PIN."))
            await load(venueID: v)
        } catch let e as APIError {
            banner = (.error, e.errorDescription ?? "Couldn't add staff")
        } catch {
            banner = (.error, error.localizedDescription)
        }
    }

    func toggle(_ s: OwnerStaff) async {
        guard let v = venueID else { return }
        _ = try? await service.setStaffStatus(staffID: s.id, status: s.isActive ? "suspended" : "active")
        await load(venueID: v)
    }
}

struct StaffManagementView: View {
    @State private var context = OwnerContext.shared
    @State private var vm = StaffMgmtViewModel()
    @State private var showAdd = false

    var body: some View {
        List {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            if let invite = vm.inviteURL, let url = URL(string: invite) {
                Section(String(localized: "staff.invite", defaultValue: "Invite link")) {
                    Text(invite).font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
                    ShareLink(item: url) { Label("Share invite", systemImage: "square.and.arrow.up") }
                }
            }

            Section {
                Button { showAdd = true } label: { Label("Add staff", systemImage: "person.badge.plus") }
            }

            Section(String(localized: "staff.roster", defaultValue: "Team")) {
                if vm.staff.isEmpty && !vm.isLoading {
                    Text("No staff yet.").foregroundStyle(.secondary)
                }
                ForEach(vm.staff) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name).font(.headline)
                            Text(s.isPending ? String(localized: "staff.pending", defaultValue: "Pending — hasn't set a PIN")
                                 : (s.isActive ? String(localized: "staff.active", defaultValue: "Active")
                                    : String(localized: "staff.suspended", defaultValue: "Suspended")))
                                .font(.caption)
                                .foregroundStyle(s.isPending ? Brand.warning : (s.isActive ? Brand.success : Brand.stone500))
                        }
                        Spacer()
                        Button(s.isActive ? String(localized: "staff.suspend", defaultValue: "Suspend")
                                          : String(localized: "staff.reactivate", defaultValue: "Reactivate")) {
                            Task { await vm.toggle(s) }
                        }
                        .buttonStyle(.bordered)
                        .tint(s.isActive ? Brand.danger : Brand.success)
                    }
                }
            }

            Section {
                NavigationLink { JoinQRView() } label: { Label("Venue join QR", systemImage: "qrcode") }
            }
        }
        .navigationTitle(Text("Staff", comment: "Staff management title"))
        .toolbar { VenueSwitcher(context: context) }
        .task(id: context.selectedVenueID) {
            await context.loadVenues()
            if let v = context.selectedVenueID { await vm.load(venueID: v) }
        }
        .sheet(isPresented: $showAdd) {
            AddStaffSheet { name in Task { await vm.add(name: name) } }
        }
    }
}

private struct AddStaffSheet: View {
    var onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Staff name", text: $name)
                    .textContentType(.name)
            } .navigationTitle(Text("Add staff", comment: "Add staff title")).zInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(name.trimmingCharacters(in: .whitespaces)); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).count < 2)
                }
            }
        }
    }
}

// MARK: - Join-QR generator

struct JoinQRView: View {
    @State private var context = OwnerContext.shared

    private func joinURL(_ venueID: String) -> String {
        "\(AppConfig.apiBaseURL.absoluteString)/j/\(venueID)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let v = context.selectedVenueID {
                    let url = joinURL(v)
                    if let img = QRImage.generate(from: url, scale: 12) {
                        img.interpolation(.none)
                            .resizable().scaledToFit()
                            .frame(maxWidth: 280)
                            .padding(20)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text("Customers scan this to join and add your loyalty card.",
                         comment: "Join QR caption")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Text(url).font(.caption2).foregroundStyle(.tertiary).textSelection(.enabled)
                    if let link = URL(string: url) {
                        ShareLink(item: link) { Label("Share join link", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent).tint(Brand.orange)
                    }
                } else {
                    EmptyStateView(systemImage: "qrcode", title: String(localized: "joinqr.select", defaultValue: "Select a venue"))
                }
            }
            .padding(20)
        }
        .background(Brand.stone.ignoresSafeArea())
        .navigationTitle(Text("Join QR", comment: "Join QR title"))
        .toolbar { VenueSwitcher(context: context) }
        .task { await context.loadVenues() }
    }
}
