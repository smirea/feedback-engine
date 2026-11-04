#if canImport(UIKit)
import ImageIO
import Security
import SwiftUI
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

    struct Project: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
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
        func projects() async throws -> [Project] {
            struct View: Decodable {
                struct Row: Decodable { let id: String; let name: String; let order: Double; let createdAt: Double }
                let projects: [Row]
            }
            let view: View = try decode(await send("GET", "api/view"))
            return view.projects.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }.map { Project(id: $0.id, name: $0.name) }
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
            _ = try await send("PATCH", "api/tasks", query: ["id": task.id], json: edit)
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

    private static let projectsKey = "feetback.procrastimate.projects"
    private static let lastProjectKey = "feetback.procrastimate.project"

    /// The projects from the last time the picker loaded them, so it opens filled.
    static var cachedProjects: [Project] {
        get { UserDefaults.standard.data(forKey: projectsKey).flatMap { try? JSONDecoder().decode([Project].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: projectsKey) }
    }

    /// The project of the last post, or nil for the Inbox.
    static var lastProject: String? {
        get { UserDefaults.standard.string(forKey: lastProjectKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastProjectKey) }
    }
}

/// Picks the project, and the task's name when there is more than one item, then posts.
struct ProcrastimateSheet: View {
    let session: Session
    let link: Procrastimate.Link
    let close: () -> Void
    @State private var projects = Procrastimate.cachedProjects
    @State private var selection = Procrastimate.lastProject
    @State private var name = ""
    @State private var loadError: String?
    @State private var postError: String?
    @State private var posting = false
    @FocusState private var naming: Bool

    static func controller(session: Session, link: Procrastimate.Link) -> UIViewController {
        let host = UIHostingController<ProcrastimateSheet?>(rootView: nil)
        host.rootView = ProcrastimateSheet(session: session, link: link) { [weak host] in host?.dismiss(animated: true) }
        host.overrideUserInterfaceStyle = .dark
        host.sheetPresentationController?.detents = [.medium(), .large()]
        return host
    }

    private var title: String {
        session.items.count == 1 ? session.items[0].text : name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                if session.items.count > 1 {
                    Section("Name") {
                        TextField("Task name", text: $name)
                            .focused($naming)
                            .submitLabel(.done)
                    }
                } else {
                    Section("Task") { Text(title).lineLimit(3) }
                }
                Section {
                    Picker("Project", selection: $selection) {
                        Label("Inbox", systemImage: "tray").tag(String?.none)
                        ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    HStack {
                        Text("Project")
                        if projects.isEmpty && loadError == nil { ProgressView().controlSize(.mini) }
                    }
                } footer: {
                    if let loadError { Text(loadError).foregroundStyle(.red) }
                }
                if let postError {
                    Section { Text(postError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add to ProcrastiMate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    if posting {
                        ProgressView()
                    } else {
                        Button("Add", action: post).disabled(title.isEmpty)
                    }
                }
            }
            .disabled(posting)
        }
        .dynamicTypeSize(...EditorView.largestTextSize)
        .interactiveDismissDisabled(posting)
        .task { await load() }
        .onAppear { naming = session.items.count > 1 }
    }

    private func load() async {
        do {
            let loaded = try await Procrastimate.Client(link).projects()
            projects = loaded
            Procrastimate.cachedProjects = loaded
            if let selected = selection, !loaded.contains(where: { $0.id == selected }) { selection = nil }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func post() {
        posting = true
        postError = nil
        let items = session.items
        let project = selection.flatMap { id in projects.first { $0.id == id } }
        let title = title
        let json = session.json
        let image = AnnotatedImage.render(session.capture, items: items).cgImage
        Task {
            do {
                guard let image else { throw Procrastimate.Failure.imageTooLarge }
                let client = try Procrastimate.Client(link)
                let encoded = try await Task.detached(priority: .userInitiated) { try Procrastimate.TaskImage(image) }.value
                _ = try await client.post(title: title, notes: json, projectId: project?.id, image: encoded)
                Procrastimate.lastProject = project?.id
                session.shared.formUnion(items)
                session.toast = "Added to \(project?.name ?? "Inbox") in ProcrastiMate"
                close()
            } catch {
                postError = error.localizedDescription
                posting = false
            }
        }
    }
}
#endif
