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
    public var headers: @MainActor () async throws -> [String: String]
    /// Added to the URL's query.
    public var query: @MainActor () async throws -> [String: String]

    public init(name: String, url: URL, image: Image? = nil, headers: [String: String] = [:], query: [String: String] = [:]) {
        self.init(name: name, url: url, image: image, headers: { headers }, query: { query })
    }

    /// `headers` and `query` run for every post and again on a retry, so they can read what did not
    /// exist when the app started, such as the token of a user who signed in since. What they throw
    /// is shown as the post's failure, under its `LocalizedError` description.
    public init(
        name: String,
        url: URL,
        image: Image? = nil,
        headers: @escaping @MainActor () async throws -> [String: String],
        query: @escaping @MainActor () async throws -> [String: String] = { [:] }
    ) {
        self.name = name
        self.url = url
        self.image = image
        self.headers = headers
        self.query = query
    }
}

struct WebhookPost: Sendable {
    struct File: Sendable, Equatable {
        let part: String
        let name: String
        let type: String
        let data: Data
    }

    /// Made once per post and sent again on a retry, so a server can tell a retry from a second post.
    let id: String
    let title: String
    let files: [File]
}

/// What a post carries beside its `id` and `title`. An app's webhook sends the image export as PNG
/// and the JSON export, as `image` and `report`. A saved webhook sends the image and the JSON export
/// if it was saved with them, as `image` and `feedback`, and the environment as `device`.
enum WebhookContents: Sendable {
    case report
    case saved(image: ImageEncoding?, feedback: Bool)

    /// `image` encodes the image export, drawn only when the post carries it.
    func files(image: (ImageEncoding) -> Data, report: String, environment: [ContextEntry]) -> [WebhookPost.File] {
        func picture(_ encoding: ImageEncoding) -> WebhookPost.File {
            switch encoding {
            case .png: .init(part: "image", name: "feedback.png", type: "image/png", data: image(encoding))
            case .jpeg: .init(part: "image", name: "feedback.jpg", type: "image/jpeg", data: image(encoding))
            }
        }
        let json = { (part: String, name: String, text: String) in WebhookPost.File(part: part, name: name, type: "application/json", data: Data(text.utf8)) }
        switch self {
        case .report:
            return [picture(.png), json("report", "feedback.json", report)]
        case .saved(let encoding, let feedback):
            return (encoding.map { [picture($0)] } ?? [])
                + (feedback ? [json("feedback", "feedback.json", report)] : [])
                + [json("device", "device.json", Report.deviceJSON(environment))]
        }
    }
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

    /// One `multipart/form-data` request with the fields `id` and `title` and then the post's files,
    /// as a browser's `FormData` sends them. Reads the headers and the query as they are now.
    @MainActor
    func request(_ post: WebhookPost, boundary: String = "feedback-\(UUID().uuidString)") async throws -> URLRequest {
        let (headers, query) = (try await headers(), try await query())
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
        for file in post.files { part(file.part, file: (file.name, file.type), file.data) }
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
