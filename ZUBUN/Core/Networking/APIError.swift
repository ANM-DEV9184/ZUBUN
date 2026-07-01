//
//  APIError.swift
//  ZUBUN
//
//  Unified error type for the REST + SDK networking layers.
//

import Foundation

enum APIError: Error, LocalizedError, Equatable {
    /// Backend returned HTTP 429 — caller should back off and show a toast.
    case rateLimited
    /// No network / request could not be sent. Caller may enqueue for offline replay.
    case offline
    /// A typed result code the server returned in the JSON envelope (e.g. `device_mismatch`).
    case result(ResultCode)
    /// Non-2xx with a server-supplied message/code.
    case server(status: Int, code: String?, message: String?)
    /// Could not decode the response into the expected shape.
    case decoding(String)
    /// The app config is incomplete (e.g. anon key not set).
    case notConfigured(String)
    /// Anything else.
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Too many attempts. Please wait a moment and try again."
        case .offline:
            return "You appear to be offline. We'll retry automatically."
        case .result(let code):
            return code.userMessage
        case .server(let status, let code, let message):
            return message ?? code ?? "Server error (\(status))."
        case .decoding(let detail):
            return "Unexpected response. (\(detail))"
        case .notConfigured(let detail):
            return detail
        case .unknown(let detail):
            return detail
        }
    }
}
