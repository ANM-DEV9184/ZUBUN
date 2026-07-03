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
    /// Most recent invite link to share/copy after adding a staffer, plus who
    /// it's for (the link is single-use and tied to that one staffer).
    var inviteURL: String?
    var inviteName: String?
    private var venueID: String?
    private let service = OwnerService()

    func load(venueID: String) async {
        self.venueID = venueID
        isLoading = true; defer { isLoading = false }
        staff = (try? await service.venueStaff(venueID: venueID)) ?? []
    }

    func add(name: String) async {
        // Fall back to the app-wide selected venue if the screen's own copy
        // hasn't landed yet (the load task can race the venue list fetch).
        guard let v = venueID ?? OwnerContext.shared.selectedVenueID else {
            banner = (.error, String(localized: "staff.novenue", defaultValue: "Select a venue first, then add staff."))
            return
        }
        venueID = v
        guard name.count >= 2 else {
            banner = (.error, String(localized: "staff.shortname", defaultValue: "Enter a name (at least 2 letters)."))
            return
        }
        do {
            let invite = try await service.addStaff(venueID: v, name: name)
            inviteURL = invite.inviteUrl
            inviteName = name
            banner = (.info, String(localized: "staff.added", defaultValue: "\(name) added — now share their personal invite so they can set a PIN."))
            await load(venueID: v)
        } catch let e as APIError {
            banner = (.error, e.errorDescription ?? "Couldn't add staff")
        } catch {
            banner = (.error, error.localizedDescription)
        }
    }

    func toggle(_ s: OwnerStaff) async {
        guard let v = venueID ?? OwnerContext.shared.selectedVenueID else { return }
        _ = try? await service.setStaffStatus(staffID: s.id, status: s.isActive ? "suspended" : "active")
        await load(venueID: v)
    }

    /// Re-fetch a pending staffer's invite link and surface it for re-sharing.
    func loadInvite(for s: OwnerStaff) async {
        if let url = try? await service.staffInvite(staffID: s.id), !url.isEmpty {
            inviteURL = url; inviteName = s.name
        } else {
            banner = (.info, String(localized: "staff.already_onboarded",
                                    defaultValue: "\(s.name) has already set up their account."))
        }
    }

    func remove(_ s: OwnerStaff) async {
        guard let v = venueID ?? OwnerContext.shared.selectedVenueID else { return }
        let res = try? await service.removeStaff(staffID: s.id)
        banner = (.info, res == "removed_soft"
                  ? String(localized: "staff.removed_soft", defaultValue: "\(s.name) removed (had activity, so archived).")
                  : String(localized: "staff.removed", defaultValue: "\(s.name) removed."))
        if inviteName == s.name { inviteURL = nil; inviteName = nil }
        await load(venueID: v)
    }
}

struct StaffManagementView: View {
    @State private var context = OwnerContext.shared
    @State private var vm = StaffMgmtViewModel()
    @State private var showAdd = false
    @State private var removeTarget: OwnerStaff?

    var body: some View {
        List {
            if let banner = vm.banner { Section { InlineBanner(kind: banner.0, message: banner.1) } }

            if let invite = vm.inviteURL, let url = URL(string: invite) {
                let who = vm.inviteName ?? String(localized: "staff.thisperson", defaultValue: "this staffer")
                let venue = context.selectedVenue?.name ?? ""
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label {
                            Text("\(who)'s personal invite", comment: "Invite header with name")
                                .font(.headline)
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(Brand.orange)
                        }

                        Text("This link is just for \(who). Send it only to them — they open it once to set their own PIN, then it stops working. It can't be reused by anyone else.",
                             comment: "Invite explanation")
                            .font(.caption).foregroundStyle(.secondary)

                        ShareLink(
                            item: url,
                            subject: Text("Your ZUBUN staff invite", comment: "Invite share subject"),
                            message: Text("Hi \(who), here's your personal link to join \(venue) on ZUBUN. Tap it to set your PIN and start clocking in — it's just for you.", comment: "Invite share message")
                        ) {
                            Label("Share \(who)'s invite", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                        }

                        Text(invite)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Staff invite", comment: "Invite section header")
                } footer: {
                    Text("Tip: the person you just added shows as “Pending” below until they open the link and set a PIN.",
                         comment: "Invite section footer")
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
                        Menu {
                            if s.isPending {
                                Button {
                                    Task { await vm.loadInvite(for: s) }
                                } label: { Label("Share invite", systemImage: "square.and.arrow.up") }
                            }
                            Button {
                                Task { await vm.toggle(s) }
                            } label: {
                                Label(s.isActive ? "Suspend" : "Reactivate",
                                      systemImage: s.isActive ? "pause.circle" : "play.circle")
                            }
                            Button(role: .destructive) { removeTarget = s } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title3)
                        }
                    }
                }
            }

            Section {
                NavigationLink { JoinQRView() } label: { Label("Venue join QR", systemImage: "qrcode") }
            }
        }
        .navigationTitle(Text("Staff", comment: "Staff management title"))
        .toolbar { VenueSwitcher(context: context) }
        .confirmationDialog(removeTarget.map { "Remove \($0.name)?" } ?? "Remove staffer?",
                            isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let s = removeTarget { Task { await vm.remove(s) } }
                removeTarget = nil
            }
            Button("Cancel", role: .cancel) { removeTarget = nil }
        } message: {
            Text("Removes this person from your team and revokes their access. If they've already stamped or clocked in, their history is kept.")
        }
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
