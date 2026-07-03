//
//  SessionStore.swift
//  ZUBUN
//
//  Persists the three independent role sessions (a device may hold more than
//  one — e.g. a customer who also owns a venue). Tokens in Keychain; light,
//  non-secret display metadata in UserDefaults so the launch router can decide
//  which experience to resume without a Keychain round-trip on every read.
//

import Foundation
import Observation

/// A persisted staff session (bearer JWT + identifying display fields).
struct StaffSession: Codable, Equatable, Sendable {
    var token: String
    var staffID: String
    var displayName: String
    var venueID: String
    var expiresAt: Date?
}

@MainActor
@Observable
final class SessionStore {
    static let shared = SessionStore()

    private enum Key {
        static let staff = "zubun.session.staff"
        static let customerToken = "zubun.session.customer"   // Supabase access token
        static let customerRefresh = "zubun.session.customer.refresh" // Supabase refresh token
        static let ownerToken = "zubun.session.owner"         // Supabase access token
        static let ownerRefresh = "zubun.session.owner.refresh" // Supabase refresh token
        static let lastRole = "zubun.session.lastRole"
    }

    // Mirrored, observable state for the UI/router.
    private(set) var staff: StaffSession?
    private(set) var hasCustomerSession: Bool = false
    private(set) var hasOwnerSession: Bool = false
    var lastRole: AppRole? {
        get { UserDefaults.standard.string(forKey: Key.lastRole).flatMap(AppRole.init) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: Key.lastRole) }
    }

    private init() {
        if let raw = Keychain.get(Key.staff),
           let data = raw.data(using: .utf8),
           let session = try? JSONDecoder.zubun.decode(StaffSession.self, from: data) {
            staff = session
        }
        hasCustomerSession = Keychain.get(Key.customerToken) != nil
        hasOwnerSession = Keychain.get(Key.ownerToken) != nil
    }

    // MARK: Staff

    func saveStaff(_ session: StaffSession) {
        staff = session
        if let data = try? JSONEncoder.zubun.encode(session),
           let raw = String(data: data, encoding: .utf8) {
            Keychain.set(raw, for: Key.staff)
        }
        lastRole = .staff
    }

    func clearStaff() {
        staff = nil
        Keychain.remove(Key.staff)
    }

    // Non-secret hints so a returning staffer re-signs in with just their PIN
    // (the device is already bound to one venue). Kept across sign-out.
    var lastStaffVenueID: String? {
        get { UserDefaults.standard.string(forKey: "zubun.staff.lastVenue") }
        set { UserDefaults.standard.set(newValue, forKey: "zubun.staff.lastVenue") }
    }
    var lastStaffName: String? {
        get { UserDefaults.standard.string(forKey: "zubun.staff.lastName") }
        set { UserDefaults.standard.set(newValue, forKey: "zubun.staff.lastName") }
    }
    func forgetStaffVenue() {
        UserDefaults.standard.removeObject(forKey: "zubun.staff.lastVenue")
        UserDefaults.standard.removeObject(forKey: "zubun.staff.lastName")
    }

    // MARK: Customer / Owner (Supabase access tokens)

    func saveCustomerToken(_ token: String, refresh: String? = nil) {
        Keychain.set(token, for: Key.customerToken)
        if let refresh { Keychain.set(refresh, for: Key.customerRefresh) }
        hasCustomerSession = true
        lastRole = .customer
    }

    var customerToken: String? { Keychain.get(Key.customerToken) }
    var customerRefreshToken: String? { Keychain.get(Key.customerRefresh) }

    func clearCustomer() {
        Keychain.remove(Key.customerToken)
        Keychain.remove(Key.customerRefresh)
        hasCustomerSession = false
    }

    func saveOwnerToken(_ token: String, refresh: String? = nil) {
        Keychain.set(token, for: Key.ownerToken)
        if let refresh { Keychain.set(refresh, for: Key.ownerRefresh) }
        hasOwnerSession = true
        lastRole = .owner
    }

    var ownerToken: String? { Keychain.get(Key.ownerToken) }
    var ownerRefreshToken: String? { Keychain.get(Key.ownerRefresh) }

    /// Owner-app role from the JWT ("owner" or "manager"). Managers get a
    /// restricted Owner experience.
    var ownerRole: String? { ownerToken.flatMap { JWTPayload.decode($0)?.appMetadata?.role } }
    var isManager: Bool { ownerRole == "manager" }
    var isAdmin: Bool { ownerRole == "admin" }

    func clearOwner() {
        Keychain.remove(Key.ownerToken)
        Keychain.remove(Key.ownerRefresh)
        hasOwnerSession = false
    }
}

enum AppRole: String, CaseIterable, Identifiable, Sendable {
    case customer, staff, owner
    var id: String { rawValue }

    var title: String {
        switch self {
        case .customer: return String(localized: "role.customer", defaultValue: "Customer")
        case .staff:    return String(localized: "role.staff", defaultValue: "Staff")
        case .owner:    return String(localized: "role.owner", defaultValue: "Owner")
        }
    }

    var subtitle: String {
        switch self {
        case .customer: return String(localized: "role.customer.sub", defaultValue: "Your loyalty cards & rewards")
        case .staff:    return String(localized: "role.staff.sub", defaultValue: "Scan, stamp & clock in")
        case .owner:    return String(localized: "role.owner.sub", defaultValue: "Manage your venue")
        }
    }

    var systemImage: String {
        switch self {
        case .customer: return "wallet.pass"
        case .staff:    return "qrcode.viewfinder"
        case .owner:    return "chart.bar.xaxis"
        }
    }
}
