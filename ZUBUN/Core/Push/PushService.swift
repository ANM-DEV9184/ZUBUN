//
//  PushService.swift
//  ZUBUN
//
//  Registers this device's APNs token with the backend so the server can target
//  it. Contract (backend must implement — see docs/PUSH_BACKEND.md):
//    POST /api/push/register  { token, platform: "ios", role }
//    Auth: the role's bearer (staff JWT, or customer/owner Supabase token).
//

import Foundation

struct PushService {
    var api = APIClient()

    /// Ignores the response body shape (any 2xx = success).
    private struct AnyOK: Decodable {}

    @discardableResult
    func register(token: String, role: String, auth: AuthMode) async -> Bool {
        struct Body: Encodable { let token: String; let platform: String; let role: String }
        do {
            let _: AnyOK = try await api.post("/api/push/register",
                                              body: Body(token: token, platform: "ios", role: role),
                                              auth: auth)
            return true
        } catch {
            return false // endpoint not deployed yet / offline — safe to ignore
        }
    }
}
