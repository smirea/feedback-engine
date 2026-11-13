import Foundation
import SwiftUI

/// One entry of the Share menu that posts the feedback to a server of the app's own, such as one
/// that files a GitHub issue. `docs/webhooks.md` has the request.
public struct FeedbackWebhook {
    /// The entry's name in the Share menu, such as `GitHub Issue`.
    public var name: String
    public var url: URL
    /// An icon beside the name, such as `Feedback.githubIcon`.
    public var image: Image?
    /// Sent with the post, such as `Authorization`. Whatever an app sends can be read out of it.
    public var headers: [String: String]
    /// Added to the URL's query.
    public var query: [String: String]

    public init(name: String, url: URL, image: Image? = nil, headers: [String: String] = [:], query: [String: String] = [:]) {
        self.name = name
        self.url = url
        self.image = image
        self.headers = headers
        self.query = query
    }
}

struct WebhookPost: Sendable {
    /// Made once per post and sent again on a retry, so a server can tell a retry from a second post.
    let id: String
    let title: String
    /// The image export, as PNG.
    let image: Data
    /// The JSON export.
    let report: Data
}

extension FeedbackWebhook {
    enum Failure: LocalizedError {
        case refused(name: String, status: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .refused(let name, let status, let message): message.map { "\(name): \($0)" } ?? "\(name) answered \(status)."
            }
        }
    }

    /// One `multipart/form-data` request with the fields `id` and `title` and the files `image` and
    /// `report`, as a browser's `FormData` sends them.
    func request(_ post: WebhookPost, boundary: String = "feedback-\(UUID().uuidString)") -> URLRequest {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var items = (components.queryItems ?? []).filter { query[$0.name] == nil }
        items += query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items.isEmpty ? nil : items

        var body = Data()
        func part(_ name: String, file: (name: String, type: String)? = nil, _ data: Data) {
            var head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\""
            if let file { head += "; filename=\"\(file.name)\"\r\nContent-Type: \(file.type)" }
            body += Data("\(head)\r\n\r\n".utf8) + data + Data("\r\n".utf8)
        }
        part("id", Data(post.id.utf8))
        part("title", Data(post.title.utf8))
        part("image", file: ("feedback.png", "image/png"), post.image)
        part("report", file: ("feedback.json", "application/json"), post.report)
        body += Data("--\(boundary)--\r\n".utf8)

        var request = URLRequest(url: components.url!, timeoutInterval: 60)
        request.httpMethod = "POST"
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    /// What an answer means: the link of a post that landed, for the toast, or the failure. The link
    /// is the server's to choose, so only a web address is kept: the toast opens it.
    static func link(name: String, request: URLRequest, status: Int, body: Data) throws -> URL? {
        struct Answer: Decodable {
            let url: String?
            let message: String?
        }
        let answer = try? JSONDecoder().decode(Answer.self, from: body)
        guard (200..<300).contains(status) else {
            throw Problem.request("POST", request.url!, status: status, body: body, error: Failure.refused(name: name, status: status, message: answer?.message))
        }
        guard let link = answer?.url.flatMap(URL.init(string:)), ["http", "https"].contains(link.scheme?.lowercased()) else { return nil }
        return link
    }

    /// Sends one post and returns the link the server answered with, if any.
    static func send(_ request: URLRequest, name: String) async throws -> URL? {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Problem.request("POST", request.url!, status: nil, body: nil, error: error)
        }
        return try link(name: name, request: request, status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }
}
