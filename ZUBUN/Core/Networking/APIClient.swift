//
//  APIClient.swift
//  ZUBUN
//
//  One client for the Next.js REST surface (https://zubun.io). Injects auth +
//  X-Device-Id, encodes/decodes JSON, maps HTTP 429 -> .rateLimited and the
//  `{ result }` envelope -> typed errors where appropriate.
//

import Foundation

/// Which credential to attach to a request.
enum AuthMode {
    case none
    /// No bearer, but sends X-Device-Id — used by staff login/onboard (spec §9.2).
    case deviceOnly
    /// Staff bearer JWT (spec §9.1) — also forces the X-Device-Id header.
    case staff
    /// Supabase access token for /api/customer/* (spec §9.3).
    case customer
    /// Owner Supabase access token for /api/dashboard/* writes.
    case owner
}

struct APIClient {
    var baseURL: URL = AppConfig.apiBaseURL
    var session: URLSession = .shared
    /// Injected so tests / previews can stub the store.
    var sessionStore: SessionStore = .shared

    // MARK: Public verbs

    func get<Response: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        auth: AuthMode = .none,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        try await send(path, method: "GET", query: query, body: Optional<Empty>.none, auth: auth)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        auth: AuthMode = .none,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        try await send(path, method: "POST", query: [], body: body, auth: auth)
    }

    /// POST with no decoded body needed.
    @discardableResult
    func postResult<Body: Encodable>(_ path: String, body: Body, auth: AuthMode = .none) async throws -> ResultEnvelope {
        try await send(path, method: "POST", query: [], body: body, auth: auth)
    }

    // MARK: Core

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem],
        body: Body?,
        auth: AuthMode
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.unknown("Bad URL for \(path)")
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.unknown("Bad URL for \(path)") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder.zubun.encode(body)
        }

        try attachAuth(auth, to: &request)

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

        guard let http = response as? HTTPURLResponse else {
            throw APIError.unknown("No HTTP response")
        }

        if http.statusCode == 429 { throw APIError.rateLimited }

        guard (200..<300).contains(http.statusCode) else {
            // Try to surface a server-provided code/message.
            let env = try? JSONDecoder.zubun.decode(ServerError.self, from: data)
            throw APIError.server(status: http.statusCode, code: env?.error ?? env?.result, message: env?.message)
        }

        do {
            return try JSONDecoder.zubun.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding("\(Response.self): \(error.localizedDescription)")
        }
    }

    private func attachAuth(_ auth: AuthMode, to request: inout URLRequest) throws {
        switch auth {
        case .none:
            break
        case .deviceOnly:
            request.setValue(DeviceID.current, forHTTPHeaderField: "X-Device-Id")
        case .staff:
            guard let token = sessionStore.staff?.token else {
                throw APIError.result(.invalidCredentials)
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(DeviceID.current, forHTTPHeaderField: "X-Device-Id")
        case .customer:
            guard let token = sessionStore.customerToken else {
                throw APIError.notConfigured("Not signed in.")
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .owner:
            guard let token = sessionStore.ownerToken else {
                throw APIError.notConfigured("Not signed in.")
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

/// Empty body sentinel for GETs.
private struct Empty: Encodable {}

private struct ServerError: Decodable {
    let error: String?
    let result: String?
    let message: String?
}
