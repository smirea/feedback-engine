#if canImport(UIKit)
import Foundation
import UIKit

/// Opens a GitHub issue with the image export attached and the JSON export in the body.
public enum GitHub {
    enum Failure: LocalizedError {
        case unauthorized
        case server(status: Int, message: String?)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unauthorized: "GitHub refused the token."
            case .server(404, _): "GitHub answered 404. The token needs write access to the repository, and attachments take only some apps' tokens, such as GitHub CLI's."
            case .server(let status, let message): message.map { "GitHub: \($0)" } ?? "GitHub answered \(status)."
            case .unreadable: "GitHub sent a response Feetback could not read."
            }
        }
    }

    /// An issue body holds at most 65,536 characters. Past this, the JSON goes to a secret gist.
    static let bodyLimit = 65_000

    struct Client: Sendable {
        let token: String

        /// The 100 repositories pushed to most recently that the token can write to.
        func repositories() async throws -> [PostOption] {
            struct Repository: Decodable {
                struct Permissions: Decodable { let push: Bool }
                let full_name: String
                let permissions: Permissions?
            }
            let repositories: [Repository] = try decode(await send("GET", "https://api.github.com/user/repos?sort=pushed&per_page=100"))
            return repositories.filter { $0.permissions?.push == true }.map { PostOption(id: $0.full_name, name: $0.full_name) }
        }

        func issue(in repository: String, title: String, summary: String, image: (data: Data, name: String, type: String), json: String) async throws -> (number: Int, url: String) {
            struct Repository: Decodable { let id: Int64 }
            let target: Repository = try decode(await send("GET", "https://api.github.com/repos/\(repository)"))
            let imageURL = try await attach(image.data, name: image.name, type: image.type, to: target.id)
            var text = "\(summary)\n\n\(Self.markdown(json: json, link: nil, image: imageURL))"
            if text.count > bodyLimit {
                text = "\(summary)\n\n\(Self.markdown(json: json, link: try await gist(json), image: imageURL))"
            }
            struct NewIssue: Encodable { let title: String; let body: String }
            struct Issue: Decodable { let number: Int; let html_url: String }
            let issue: Issue = try decode(await send("POST", "https://api.github.com/repos/\(repository)/issues", json: NewIssue(title: title, body: text)))
            return (issue.number, issue.html_url)
        }

        /// The endpoint `gh issue create --attach` uses. The REST API has no issue attachments, and
        /// this one takes only images and videos, so the JSON cannot be attached as a file.
        private func attach(_ data: Data, name: String, type: String, to repository: Int64) async throws -> String {
            var url = URL(string: "https://uploads.github.com/user-attachments/assets")!
            url.append(queryItems: [
                URLQueryItem(name: "name", value: name),
                URLQueryItem(name: "content_type", value: type),
                URLQueryItem(name: "repository_id", value: String(repository)),
            ])
            struct Asset: Decodable { let url: String }
            let asset: Asset = try decode(await send("POST", url.absoluteString, body: data, type: "application/octet-stream"))
            return asset.url
        }

        private func gist(_ json: String) async throws -> String {
            struct File: Encodable { let content: String }
            struct NewGist: Encodable { let description: String; let `public`: Bool; let files: [String: File] }
            struct Gist: Decodable { let html_url: String }
            let gist: Gist = try decode(await send("POST", "https://api.github.com/gists", json: NewGist(
                description: "Feetback feedback.json", public: false, files: ["feedback.json": File(content: json)]
            )))
            return gist.html_url
        }

        private static func markdown(json: String, link: String?, image: String) -> String {
            if let link { return "![feedback.png](\(image))\n\nThe JSON export is too long for an issue: [feedback.json](\(link))" }
            let longestRun = json.split(whereSeparator: { $0 != "`" }).map(\.count).max() ?? 0
            let fence = String(repeating: "`", count: max(3, longestRun + 1))
            return "![feedback.png](\(image))\n\n<details>\n<summary>feedback.json</summary>\n\n\(fence)json\n\(json)\n\(fence)\n\n</details>"
        }

        private func send(_ method: String, _ url: String, json: some Encodable) async throws -> Data {
            try await send(method, url, body: JSONEncoder().encode(json), type: "application/json")
        }

        private func send(_ method: String, _ url: String, body: Data? = nil, type: String? = nil) async throws -> Data {
            var request = URLRequest(url: URL(string: url)!, timeoutInterval: 60)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("Feetback", forHTTPHeaderField: "User-Agent")
            if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.unreadable }
            if status == 401 { throw Failure.unauthorized }
            guard (200..<300).contains(status) else {
                struct Body: Decodable {
                    struct Detail: Decodable { let message: String? }
                    let message: String?
                    let errors: [Detail]?
                }
                let body = try? JSONDecoder().decode(Body.self, from: data)
                let message = ([body?.message] + (body?.errors ?? []).map(\.message)).compactMap { $0 }.joined(separator: ": ")
                throw Failure.server(status: status, message: message.isEmpty ? nil : message)
            }
            return data
        }

        private func decode<T: Decodable>(_ data: Data) throws -> T {
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw Failure.unreadable }
        }
    }
}

struct GitHubDestination: Destination {
    let token: String

    var key: String { "github" }
    var sheetTitle: String { "New GitHub Issue" }
    var containerTitle: String { "Repository" }
    var fixedOptions: [PostOption] { [] }

    func options() async throws -> [PostOption] {
        try await GitHub.Client(token: token).repositories()
    }

    func post(_ post: Post, to option: PostOption) async throws -> String {
        let image = try Self.image(post.image)
        let issue = try await GitHub.Client(token: token).issue(
            in: option.id, title: post.title, summary: Self.items(post), image: image, json: post.json
        )
        return "Opened #\(issue.number) in \(option.name)"
    }

    /// The items as a numbered list matching the image's badges, so the issue reads without the image.
    private static func items(_ post: Post) -> String {
        post.items.enumerated().map { index, item in
            let target = post.capture.nodes[item.target]
            let code = post.capture.nearestComponent(from: item.target)?.source.map { " · `\($0.description)`" } ?? ""
            let text = item.text.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n   ")
            return "\(index + 1). **\(target.title)**\(code)\n   \(text)"
        }.joined(separator: "\n")
    }

    /// GitHub takes images up to 10 MB. A long capture's PNG can pass that, so it goes as JPEG.
    private static func image(_ image: UIImage) throws -> (data: Data, name: String, type: String) {
        if let png = image.pngData(), png.count <= 10_000_000 { return (png, "feedback.png", "image/png") }
        for quality in [0.85, 0.7, 0.5] {
            if let jpeg = image.jpegData(compressionQuality: quality), jpeg.count <= 10_000_000 { return (jpeg, "feedback.jpg", "image/jpeg") }
        }
        throw GitHub.Failure.server(status: 413, message: "The image is over GitHub's 10 MB limit.")
    }
}
#endif
