//
//  SupportService.swift
//  ZUBUN
//
//  One support client for all roles — the AuthMode passed in selects the caller's
//  credential (.owner / .customer / .staff), and the server's resolveRaiser()
//  attaches identity + tier. Talks to /api/app/support + /api/app/support/thread.
//

import Foundation
import UIKit

struct SupportService {
    var api = APIClient()
    let auth: AuthMode

    func tickets() async throws -> [AppTicket] {
        let r: AppTicketsResponse = try await api.get("/api/app/support", auth: auth)
        return r.tickets
    }

    @discardableResult
    func create(subject: String, body: String, category: String, imageDataURL: String?) async throws -> String? {
        struct Body: Encodable { let subject: String; let body: String; let category: String; let image: String? }
        let r: CreateTicketResponse = try await api.post("/api/app/support",
            body: Body(subject: subject, body: body, category: category, image: imageDataURL), auth: auth)
        return r.ticketId
    }

    func thread(ticketID: String) async throws -> AppThreadResponse {
        try await api.get("/api/app/support/thread",
                          query: [.init(name: "ticket_id", value: ticketID)], auth: auth)
    }

    func reply(ticketID: String, body: String, imageDataURL: String?) async throws {
        struct Body: Encodable { let ticketId: String; let action: String; let body: String; let image: String? }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/app/support/thread",
            body: Body(ticketId: ticketID, action: "reply", body: body, image: imageDataURL), auth: auth)
    }

    func rate(ticketID: String, rating: Int, comment: String?) async throws {
        struct Body: Encodable { let ticketId: String; let action: String; let rating: Int; let comment: String? }
        struct Ignore: Decodable {}
        let _: Ignore = try await api.post("/api/app/support/thread",
            body: Body(ticketId: ticketID, action: "rate", rating: rating, comment: comment), auth: auth)
    }
}

/// Turns picked image data into a compressed base64 data URL the server accepts
/// (`data:image/jpeg;base64,…`, ≤5 MB). Downscales large photos first.
enum SupportImage {
    static func dataURL(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let scaled = downscale(image, maxDimension: maxDimension)
        guard let jpeg = scaled.jpegData(compressionQuality: quality), jpeg.count <= 5 * 1024 * 1024 else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
