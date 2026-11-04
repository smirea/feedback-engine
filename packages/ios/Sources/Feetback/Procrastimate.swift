#if canImport(UIKit)
import ImageIO
import Security
import UIKit
import UniformTypeIdentifiers

/// Posts feedback to ProcrastiMate as one task: the image export as a task image, the JSON export as
/// its notes. Uses ProcrastiMate's agent API (`POST /api/tasks`, `PATCH /api/tasks`) and image upload
/// (`PUT /api/images`).
public enum Procrastimate {
    public enum Link: Sendable {
        /// The session ProcrastiMate keeps in the team's shared keychain group while it is signed in,
        /// as for Notouroboros. The host app needs the group in its `keychain-access-groups`
        /// entitlement, and a simulator build must be signed, even ad hoc, for the keychain to honor it.
        case shared(accessGroup: String = "FNYFHG5SV7.com.stefan.shared")
        /// A personal `pm.` token from ProcrastiMate's settings. `apiURL` is the server's origin,
        /// without `/api`.
        case token(apiURL: URL, token: String)
    }

    enum Failure: LocalizedError {
        case signedOut
        case server(status: Int, message: String?)
        case unreadable
        case imageTooLarge

        var errorDescription: String? {
            switch self {
            case .signedOut: "ProcrastiMate is signed out. Sign in there, then try again."
            case .server(let status, let message): message.map { "ProcrastiMate: \($0)" } ?? "ProcrastiMate answered \(status)."
            case .unreadable: "ProcrastiMate sent a response Feetback could not read."
            case .imageTooLarge: "The image could not be made small enough to upload."
            }
        }
    }

    struct Client: Sendable {
        let apiURL: URL
        let token: String

        init(_ link: Link) throws {
            switch link {
            case .token(let apiURL, let token):
                (self.apiURL, self.token) = (apiURL, token)
            case .shared(let accessGroup):
                struct Item: Decodable { let apiURL: String; let token: String }
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "procrastimate-link",
                    kSecAttrAccount as String: "default",
                    kSecAttrAccessGroup as String: accessGroup,
                    kSecReturnData as String: true,
                    kSecMatchLimit as String: kSecMatchLimitOne,
                ]
                var result: CFTypeRef?
                guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
                      let item = try? JSONDecoder().decode(Item.self, from: data), !item.token.isEmpty,
                      let apiURL = URL(string: item.apiURL)
                else { throw Failure.signedOut }
                (self.apiURL, self.token) = (apiURL, item.token)
            }
        }

        /// The space's projects in the app's order. `/api/view` is the only route that lists them,
        /// and it carries every task too.
        func projects() async throws -> [PostOption] {
            struct View: Decodable {
                struct Row: Decodable { let id: String; let name: String; let order: Double; let createdAt: Double }
                let projects: [Row]
            }
            let view: View = try decode(await send("GET", "api/view"))
            return view.projects.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }.map { PostOption(id: $0.id, name: $0.name) }
        }

        /// Uploads the image before the task that lists it, as ProcrastiMate's own clients do, so the
        /// task never names an image the server cannot serve. Returns the task's id.
        func post(title: String, notes: String, projectId: String?, image: TaskImage) async throws -> String {
            for (size, data) in [("full", image.full), ("thumb", image.thumb)] {
                _ = try await send("PUT", "api/images", query: ["id": image.id, "size": size], body: data, type: "image/jpeg")
            }
            struct NewTask: Encodable { let title: String; let notes: String; let projectId: String? }
            struct Task: Decodable { let id: String }
            let task: Task = try decode(await send("POST", "api/tasks", json: NewTask(title: title, notes: notes, projectId: projectId)))
            struct Ref: Encodable { let id: String; let width: Int; let height: Int }
            struct Edit: Encodable { let images: [Ref] }
            let edit = Edit(images: [Ref(id: image.id, width: image.width, height: image.height)])
            // The agent API cannot create a task with images, so a failed attach would leave a task
            // without its screenshot, and the retry would add a second one.
            do {
                _ = try await send("PATCH", "api/tasks", query: ["id": task.id], json: edit)
            } catch {
                _ = try? await send("DELETE", "api/tasks", query: ["id": task.id])
                throw error
            }
            return task.id
        }

        private func send(_ method: String, _ path: String, query: [String: String] = [:], json: some Encodable) async throws -> Data {
            try await send(method, path, query: query, body: JSONEncoder().encode(json), type: "application/json")
        }

        private func send(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil, type: String? = nil) async throws -> Data {
            var url = apiURL.appending(path: path)
            if !query.isEmpty { url.append(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }) }
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("Feetback", forHTTPHeaderField: "User-Agent")
            if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.unreadable }
            if status == 401 { throw Failure.signedOut }
            guard (200..<300).contains(status) else {
                struct Body: Decodable { let message: String? }
                throw Failure.server(status: status, message: (try? JSONDecoder().decode(Body.self, from: data))?.message)
            }
            return data
        }

        private func decode<T: Decodable>(_ data: Data) throws -> T {
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw Failure.unreadable }
        }
    }

    /// A task image's two sizes as JPEG, the only format besides WebP that ProcrastiMate stores.
    struct TaskImage: Sendable {
        let id = UUID().uuidString.lowercased()
        let full: Data
        let thumb: Data
        let width: Int
        let height: Int

        /// ProcrastiMate's own clients fit the long side to 2,048 and 320 pixels. A full-length
        /// capture is many times taller than wide, so this fits the width instead, keeping its text
        /// readable. The byte caps are the server's.
        init(_ image: CGImage) throws {
            guard let full = Self.jpeg(image, width: 2048, maxBytes: 1_500_000),
                  let thumb = Self.jpeg(image, width: 320, maxBytes: 200_000)
            else { throw Failure.imageTooLarge }
            (self.full, width, height) = full
            self.thumb = thumb.data
        }

        private static func jpeg(_ image: CGImage, width: Int, maxBytes: Int) -> (data: Data, width: Int, height: Int)? {
            var width = min(width, image.width)
            while width >= 64 {
                let height = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
                guard let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else { return nil }
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                guard let scaled = context.makeImage() else { return nil }
                for quality in [0.8, 0.65, 0.5] {
                    let data = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
                    CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                    if CGImageDestinationFinalize(destination), data.length <= maxBytes { return (data as Data, width, height) }
                }
                width = width * 3 / 4
            }
            return nil
        }
    }
}

struct ProcrastimateDestination: Destination {
    let link: Procrastimate.Link

    var key: String { "procrastimate" }
    var sheetTitle: String { "Add to ProcrastiMate" }
    var containerTitle: String { "Project" }
    var fixedOptions: [PostOption] { [PostOption(id: "", name: "Inbox", systemImage: "tray")] }

    func options() async throws -> [PostOption] {
        try await Procrastimate.Client(link).projects()
    }

    func post(_ post: Post, to option: PostOption) async throws -> String {
        guard let image = post.image.cgImage else { throw Procrastimate.Failure.imageTooLarge }
        let client = try Procrastimate.Client(link)
        let encoded = try await Task.detached(priority: .userInitiated) { try Procrastimate.TaskImage(image) }.value
        _ = try await client.post(title: post.title, notes: post.json, projectId: option.id.isEmpty ? nil : option.id, image: encoded)
        return "Added to \(option.name) in ProcrastiMate"
    }
}
#endif
