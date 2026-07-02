//
//  SupabaseService.swift
//  ZUBUN
//
//  Self-contained Supabase client over URLSession — no SPM dependency. Talks to
//  the same endpoints the official SDK uses:
//   • GoTrue auth:  {SUPABASE_URL}/auth/v1/*   (phone OTP, email/password)
//   • PostgREST RPC:{SUPABASE_URL}/rest/v1/rpc/{fn}
//
//  Used for Customer phone-OTP auth (spec §9.3) and Owner email/password auth +
//  RLS-scoped RPC reads (spec §4.3). Every request sends the public anon key as
//  `apikey`; authenticated calls add `Authorization: Bearer <accessToken>`.
//

import Foundation

@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    private let baseURL = AppConfig.supabaseURL
    private let anonKey = AppConfig.supabaseAnonKey
    private let session: URLSession = .shared

    private init() {}

    // MARK: - Customer email OTP

    /// Sends a 6-digit email OTP (GoTrue). The Supabase email template must use
    /// `{{ .Token }}` so a code (not a magic link) is delivered.
    func sendEmailOTP(_ email: String) async throws {
        struct Body: Encodable { let email: String; let createUser: Bool }
        let _: EmptyResponse = try await authPost("otp", body: Body(email: email, createUser: true))
    }

    func verifyEmailOTP(email: String, code: String) async throws -> String {
        struct Body: Encodable { let type: String; let email: String; let token: String }
        let res: TokenResponse = try await authPost("verify",
                                                     body: Body(type: "email", email: email, token: code))
        return res.accessToken
    }

    // MARK: - Owner email/password

    func ownerSignIn(email: String, password: String) async throws -> String {
        struct Body: Encodable { let email: String; let password: String }
        let res: TokenResponse = try await authPost("token", query: [.init(name: "grant_type", value: "password")],
                                                     body: Body(email: email, password: password))
        return res.accessToken
    }

    func signOut() async {
        // Best-effort server-side revoke; local clears happen in the caller.
        guard let token = SessionStore.shared.ownerToken ?? SessionStore.shared.customerToken else { return }
        var req = authRequest(path: "auth/v1/logout", method: "POST")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: req)
    }

    /// Change the signed-in user's password (GoTrue PUT /auth/v1/user).
    func updatePassword(_ newPassword: String, accessToken: String) async throws {
        struct Body: Encodable { let password: String }
        struct Ignore: Decodable {}
        var req = authRequest(path: "auth/v1/user", method: "PUT")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder.zubun.encode(Body(password: newPassword))
        let _: Ignore = try await decode(req, as: Ignore.self)
    }

    // MARK: - RPC (RLS-scoped)

    /// Calls a Postgres RPC (no params) and decodes the JSON result.
    func rpc<T: Decodable>(_ name: String, accessToken: String? = nil) async throws -> T {
        try await rpc(name, params: EmptyParams(), accessToken: accessToken)
    }

    /// Calls a Postgres RPC with typed params. Pass the caller's access token so
    /// RLS + the function's SECURITY DEFINER self-guards resolve correctly.
    func rpc<Params: Encodable, T: Decodable>(_ name: String, params: Params, accessToken: String? = nil) async throws -> T {
        guard AppConfig.isAnonKeyConfigured else {
            throw APIError.notConfigured("Supabase anon key not set in AppConfig.")
        }
        var req = authRequest(path: "rest/v1/rpc/\(name)", method: "POST")
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder.zubun.encode(params)
        return try await decode(req, as: T.self)
    }

    // MARK: - PostgREST direct table select (RLS-scoped)

    /// GET `/rest/v1/{table}` with query items, decoded as an array. Pass the
    /// owner/customer access token so RLS scopes the rows.
    func restGet<T: Decodable>(_ table: String, query: [URLQueryItem], accessToken: String?) async throws -> [T] {
        guard AppConfig.isAnonKeyConfigured else {
            throw APIError.notConfigured("Supabase anon key not set in AppConfig.")
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var req = URLRequest(url: components.url!)
        req.httpMethod = "GET"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decode(req, as: [T].self)
    }

    // MARK: - PostgREST writes (RLS-scoped)

    /// INSERT one or more rows. Set `upsertOnConflict` to merge duplicates on that
    /// column list; set `ignoreDuplicates` to skip conflicts instead of merging.
    func restInsert<Body: Encodable>(_ table: String, body: Body,
                                     upsertOnConflict: String? = nil,
                                     ignoreDuplicates: Bool = false,
                                     accessToken: String?) async throws {
        var query: [URLQueryItem] = []
        if let cols = upsertOnConflict { query.append(.init(name: "on_conflict", value: cols)) }
        var prefer = "return=minimal"
        if upsertOnConflict != nil {
            prefer += ignoreDuplicates ? ",resolution=ignore-duplicates" : ",resolution=merge-duplicates"
        }
        try await write(table, method: "POST", query: query, body: body, prefer: prefer, accessToken: accessToken)
    }

    /// PATCH (update) rows matching the query filters.
    func restPatch<Body: Encodable>(_ table: String, query: [URLQueryItem], body: Body, accessToken: String?) async throws {
        try await write(table, method: "PATCH", query: query, body: body, prefer: "return=minimal", accessToken: accessToken)
    }

    /// DELETE rows matching the query filters (e.g. `id=eq.x`).
    func restDelete(_ table: String, query: [URLQueryItem], accessToken: String?) async throws {
        try await write(table, method: "DELETE", query: query, body: Optional<EmptyParams>.none,
                        prefer: "return=minimal", accessToken: accessToken)
    }

    private func write<Body: Encodable>(_ table: String, method: String, query: [URLQueryItem],
                                        body: Body?, prefer: String, accessToken: String?) async throws {
        guard AppConfig.isAnonKeyConfigured else {
            throw APIError.notConfigured("Supabase anon key not set in AppConfig.")
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/\(table)"),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let accessToken { req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        req.setValue(prefer, forHTTPHeaderField: "Prefer")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder.zubun.encode(body)
        }
        _ = try await performVoid(req)
    }

    @discardableResult
    private func performVoid(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let code = (error as? URLError)?.code
            if code == .notConnectedToInternet || code == .networkConnectionLost || code == .timedOut {
                throw APIError.offline
            }
            throw APIError.unknown(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unknown("No HTTP response") }
        if http.statusCode == 429 { throw APIError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            let err = try? JSONDecoder.zubun.decode(SupabaseAuthError.self, from: data)
            throw APIError.server(status: http.statusCode, code: err?.errorCode, message: err?.message ?? err?.msg)
        }
        return data
    }

    // MARK: - Internals

    private func authPost<Body: Encodable, Response: Decodable>(
        _ endpoint: String,
        query: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        guard AppConfig.isAnonKeyConfigured else {
            throw APIError.notConfigured("Supabase anon key not set in AppConfig.")
        }
        var req = authRequest(path: "auth/v1/\(endpoint)", method: "POST", query: query)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder.zubun.encode(body)
        return try await decode(req, as: Response.self)
    }

    private func authRequest(path: String, method: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func decode<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let code = (error as? URLError)?.code
            if code == .notConnectedToInternet || code == .networkConnectionLost || code == .timedOut {
                throw APIError.offline
            }
            throw APIError.unknown(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unknown("No HTTP response") }
        if http.statusCode == 429 { throw APIError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            let err = try? JSONDecoder.zubun.decode(SupabaseAuthError.self, from: data)
            throw APIError.server(status: http.statusCode,
                                  code: err?.errorCode ?? err?.error,
                                  message: err?.msg ?? err?.errorDescription ?? err?.message)
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try JSONDecoder.zubun.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(T.self): \(error.localizedDescription)")
        }
    }
}

// MARK: - Wire types

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
}

private struct EmptyResponse: Decodable {}
private struct EmptyParams: Encodable {}

private struct SupabaseAuthError: Decodable {
    let error: String?
    let errorDescription: String?
    let errorCode: String?
    let msg: String?
    let message: String?
}
