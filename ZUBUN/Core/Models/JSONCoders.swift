//
//  JSONCoders.swift
//  ZUBUN
//
//  Shared coders: snake_case <-> camelCase. Dates are carried as ISO strings in
//  DTOs and parsed via DubaiDate to avoid global date-strategy coupling.
//

import Foundation

extension JSONDecoder {
    static let zubun: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

/// A dynamic JSON value for RPC params that must send EXPLICIT nulls (PostgREST
/// requires every non-defaulted named arg to be present). Use a
/// `[String: JSONParam]` as the `params:` for such RPCs.
enum JSONParam: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b):   try c.encode(b)
        case .null:          try c.encodeNil()
        }
    }

    /// Convenience: nil String -> .null.
    static func optString(_ s: String?) -> JSONParam { s.map(JSONParam.string) ?? .null }
    static func optInt(_ i: Int?) -> JSONParam { i.map(JSONParam.int) ?? .null }
}

extension JSONEncoder {
    static let zubun: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}
