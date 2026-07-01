//
//  AppConfig.swift
//  ZUBUN
//
//  Central, build-time configuration. Only PUBLIC values live here (safe to ship):
//  the Supabase URL + anon key (RLS-protected) and the Next.js API base.
//  NEVER place service-role / HMAC / Stripe secrets in the app bundle.
//

import Foundation

enum AppConfig {
    /// Supabase project URL (public). Project `cnliarflnlbocgritpxp`.
    static let supabaseURL = URL(string: "https://cnliarflnlbocgritpxp.supabase.co")!

    /// Supabase anon/publishable key (public, RLS-protected).
    /// Legacy `anon` JWT — accepted as both `apikey` and bearer by GoTrue/PostgREST.
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNubGlhcmZsbmxib2Nncml0cHhwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyODAyNjMsImV4cCI6MjA5Njg1NjI2M30.ZXu1HxhhAjwsRkIA1cd3BCoonlXRIUaLFXaoxY8l0TU"

    /// Next.js API host that fronts the staff/customer REST routes.
    static let apiBaseURL = URL(string: "https://zubun.io")!

    /// UAE-only product: all day/window math uses this zone.
    static let timeZoneIdentifier = "Asia/Dubai"

    // Billing is handled on the ZUBUN web dashboard via Stripe (B2B). The iOS app
    // shows read-only plan status only — no in-app purchase (see BillingView).

    /// Returns true while the anon key is still the placeholder, so the UI can warn
    /// instead of failing opaquely against the network.
    static var isAnonKeyConfigured: Bool {
        !supabaseAnonKey.isEmpty && supabaseAnonKey != "REPLACE_WITH_SUPABASE_ANON_KEY"
    }
}
