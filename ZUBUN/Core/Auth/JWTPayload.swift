//
//  JWTPayload.swift
//  ZUBUN
//
//  Minimal, unverified decode of a Supabase JWT's payload — used only to read
//  non-secret routing claims client-side (e.g. app_metadata.merchant_id for the
//  owner). We never trust this for security; the backend re-verifies every call.
//

import Foundation

enum JWTPayload {
    struct Claims: Decodable {
        struct AppMetadata: Decodable {
            let merchantId: String?
            let role: String?
        }
        let appMetadata: AppMetadata?
        let sub: String?
        let phone: String?
    }

    static func decode(_ token: String) -> Claims? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad to a multiple of 4.
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder.zubun.decode(Claims.self, from: data)
    }

    static func merchantID(from token: String) -> String? {
        decode(token)?.appMetadata?.merchantId
    }
}
