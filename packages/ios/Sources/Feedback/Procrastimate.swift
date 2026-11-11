#if canImport(UIKit)
import ImageIO
import Security
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Posts feedback to ProcrastiMate as one task: the image export as a task image, the JSON export as a
/// `feedback.json` attachment. Uses ProcrastiMate's agent API (`POST /api/tasks`, `PATCH /api/tasks`) and image upload
/// (`PUT /api/images`).
enum Procrastimate {
    /// ProcrastiMate keeps its session here while it is signed in, for the team's other apps.
    static let accessGroup = "FNYFHG5SV7.com.stefan.shared"

    /// Whether the app's entitlements let it read that keychain group. The Share menu lists ProcrastiMate only then,
    /// so an app outside the team never shows an entry that cannot work. A signed-out ProcrastiMate still counts:
    /// the picker says to sign in.
    static var isAvailable: Bool { Client.session().status != errSecMissingEntitlement }
    /// ProcrastiMate's `FILE_PART_BYTES` and `FILE_MAX_BYTES` (`shared/images.ts`).
    static let filePartBytes = 1_500_000
    static let fileMaxBytes = 25_000_000

    struct Project: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let icon: String?
        /// In the project's order.
        let sections: [Section]

        /// ProcrastiMate's own SF Symbol for each of its icon names (`ProjectIcons.swift` there). A
        /// project without an icon, or with one newer than this list, shows the `#` it always had.
        var systemImage: String {
            switch icon {
            case "home": "house"
            case "work": "briefcase"
            case "errands": "checklist"
            case "shopping": "cart"
            case "groceries": "basket"
            case "money": "banknote"
            case "bills": "receipt"
            case "health": "cross.case"
            case "fitness": "dumbbell"
            case "food": "fork.knife"
            case "travel": "airplane"
            case "car": "car"
            case "learning": "graduationcap"
            case "reading": "book"
            case "ideas": "lightbulb"
            case "writing": "pencil"
            case "code": "chevron.left.forwardslash.chevron.right"
            case "calendar": "calendar"
            case "family": "person.3"
            case "pets": "pawprint"
            case "garden": "leaf"
            case "cleaning": "bubbles.and.sparkles"
            case "repairs": "wrench.and.screwdriver"
            case "documents": "doc.text"
            case "email": "envelope"
            case "calls": "phone"
            case "music": "music.note"
            case "movies": "film"
            case "games": "gamecontroller"
            case "gifts": "gift"
            case "art": "paintbrush"
            case "photos": "camera"
            case "outdoors": "mountain.2"
            case "goals": "target"
            case "favorites": "star"
            case "love": "heart"
            case "someday": "moon"
            default: "number"
            }
        }
    }

    struct Section: Codable, Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    /// Where a task goes: the Inbox when `projectId` is nil, and the project's top, above its
    /// sections, when `sectionId` is.
    struct Place: Hashable, Sendable {
        var projectId: String?
        var sectionId: String?
    }

    /// The projects from the last time the picker loaded them, so it opens filled.
    static var cachedProjects: [Project] {
        get { UserDefaults.standard.data(forKey: "feedback.procrastimate.projects.v2").flatMap { try? JSONDecoder().decode([Project].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "feedback.procrastimate.projects.v2") }
    }

    /// The project of the last post, or nil for the Inbox. Its section is not kept: a new post starts
    /// at the project's top.
    static var lastProject: String? {
        get { UserDefaults.standard.string(forKey: "feedback.procrastimate.project") }
        set { UserDefaults.standard.set(newValue, forKey: "feedback.procrastimate.project") }
    }

    enum Failure: LocalizedError {
        case signedOut
        case server(status: Int, message: String?)
        case unreadable
        case imageTooLarge
        case reportTooLarge

        var errorDescription: String? {
            switch self {
            case .signedOut: "ProcrastiMate isn't signed in on this device. Open it, sign in, then try again."
            case .server(let status, let message): message.map { "ProcrastiMate: \($0)" } ?? "ProcrastiMate answered \(status)."
            case .unreadable: "ProcrastiMate sent a response Feedback could not read."
            case .imageTooLarge: "The image could not be made small enough to upload."
            case .reportTooLarge: "The JSON report is over ProcrastiMate's 25 MB file limit."
            }
        }
    }

    struct Client: Sendable {
        let apiURL: URL
        let token: String

        /// Reads the session ProcrastiMate shares through the team's keychain group, as
        /// Notouroboros does. A simulator honors the group only in a signed build, even ad hoc.
        /// An app outside the group never gets here: its Share menu has no ProcrastiMate entry.
        init() throws {
            struct Item: Decodable { let apiURL: String; let token: String }
            let (status, data) = Client.session()
            guard status == errSecSuccess, let data,
                  let item = try? JSONDecoder().decode(Item.self, from: data), !item.token.isEmpty,
                  let apiURL = URL(string: item.apiURL)
            else { throw Failure.signedOut }
            (self.apiURL, self.token) = (apiURL, item.token)
        }

        static func session() -> (status: OSStatus, data: Data?) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "procrastimate-link",
                kSecAttrAccount as String: "default",
                kSecAttrAccessGroup as String: Procrastimate.accessGroup,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            return (status, result as? Data)
        }

        /// The space's projects and their sections in the app's order. `/api/view` is the only route
        /// that lists them, and it carries every task too.
        func projects() async throws -> [Project] {
            struct View: Decodable {
                struct Row: Decodable { let id: String; let name: String; let icon: String?; let order: Double; let createdAt: Double }
                struct SectionRow: Decodable { let id: String; let projectId: String; let name: String; let order: Double; let createdAt: Double }
                let projects: [Row]
                let sections: [SectionRow]
            }
            let view: View = try decode(await send("GET", "api/view"))
            let sections = Dictionary(grouping: view.sections.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }, by: \.projectId)
            return view.projects.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }.map { row in
                Project(id: row.id, name: row.name, icon: row.icon, sections: (sections[row.id] ?? []).map { Section(id: $0.id, name: $0.name) })
            }
        }

        /// Uploads the attachments before the task that lists them, as ProcrastiMate's own clients do,
        /// so the task never names bytes the server cannot serve. Returns the task's id.
        func post(title: String, place: Place, image: TaskImage, report: Data) async throws -> String {
            guard report.count <= Procrastimate.fileMaxBytes else { throw Failure.reportTooLarge }
            for (size, data) in [("full", image.full), ("thumb", image.thumb)] {
                _ = try await send("PUT", "api/images", query: ["id": image.id, "size": size], body: data, type: "image/jpeg")
            }
            // ProcrastiMate stores a file in parts that each fit one database row.
            let reportID = UUID().uuidString.lowercased()
            for (index, start) in stride(from: 0, to: report.count, by: Procrastimate.filePartBytes).enumerated() {
                let part = report.subdata(in: start..<min(start + Procrastimate.filePartBytes, report.count))
                _ = try await send("PUT", "api/images", query: ["id": reportID, "size": "part\(index)"], body: part, type: "application/octet-stream")
            }
            struct NewTask: Encodable { let title: String; let projectId: String?; let sectionId: String? }
            struct Task: Decodable { let id: String }
            let task: Task = try decode(await send("POST", "api/tasks", json: NewTask(title: title, projectId: place.projectId, sectionId: place.sectionId)))
            // An image ref is `{id, width, height}` and a file ref `{id, name, type, bytes}`; the server
            // tells them apart by shape.
            struct Ref: Encodable { let id: String; var width: Int?; var height: Int?; var name: String?; var type: String?; var bytes: Int? }
            struct Edit: Encodable { let attachments: [Ref] }
            let edit = Edit(attachments: [
                Ref(id: image.id, width: image.width, height: image.height),
                Ref(id: reportID, name: "feedback.json", type: "application/json", bytes: report.count),
            ])
            // The agent API cannot create a task with attachments, so a failed attach would leave a
            // task without them, and the retry would add a second one.
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
            request.setValue("Feedback", forHTTPHeaderField: "User-Agent")
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

/// Picks the project and the task's name, then posts.
struct ProcrastimateSheet: View {
    let session: Session
    let close: () -> Void
    @State private var projects = Procrastimate.cachedProjects
    @State private var place = Procrastimate.Place(projectId: Procrastimate.lastProject)
    @State private var name: String
    @State private var loading = true
    @State private var loadError: String?
    @State private var postError: String?
    @State private var posting = false
    @State private var summarizing = false
    private let taskTitle: TaskTitle

    init(session: Session, close: @escaping () -> Void) {
        self.session = session
        self.close = close
        taskTitle = TaskTitle(session.capture, items: session.items)
        _name = State(initialValue: taskTitle.placeholder)
    }

    static func controller(session: Session) -> UIViewController {
        let host = UIHostingController<ProcrastimateSheet?>(rootView: nil)
        host.rootView = ProcrastimateSheet(session: session) { [weak host] in host?.dismiss(animated: true) }
        host.overrideUserInterfaceStyle = .dark
        host.sheetPresentationController?.detents = [.medium(), .large()]
        return host
    }

    private var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    HStack {
                        TextField("Task name", text: $name).submitLabel(.done)
                        if summarizing { ProgressView().accessibilityLabel("Naming the task") }
                    }
                }
                Section {
                    row("Inbox", systemImage: "tray", picked: place.projectId == nil) { place = .init() }
                    ForEach(projects) { project in
                        let open = project.id == place.projectId && !project.sections.isEmpty
                        row(project.name, systemImage: project.systemImage, picked: project.id == place.projectId && !open) {
                            place = .init(projectId: project.id)
                        }
                        // The picked project lists its sections under it, as ProcrastiMate's own menus
                        // do: its top first, as `No section`.
                        if open {
                            row("No section", systemImage: project.systemImage, picked: place.sectionId == nil, indented: true) {
                                place = .init(projectId: project.id)
                            }
                            ForEach(project.sections) { section in
                                row(section.name, systemImage: "rectangle.split.1x2", picked: place.sectionId == section.id, indented: true) {
                                    place = .init(projectId: project.id, sectionId: section.id)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Project")
                        if loading { ProgressView().controlSize(.mini) }
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
        .task { await summarize() }
    }

    private func row(_ name: String, systemImage: String, picked: Bool, indented: Bool = false, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            HStack {
                Label(name, systemImage: systemImage)
                Spacer()
                if picked { Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold) }
            }
            .padding(.leading, indented ? 28 : 0)
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func load() async {
        defer { loading = false }
        do {
            let loaded = try await Procrastimate.Client().projects()
            projects = loaded
            Procrastimate.cachedProjects = loaded
            if let id = place.projectId {
                if let project = loaded.first(where: { $0.id == id }) {
                    if let section = place.sectionId, !project.sections.contains(where: { $0.id == section }) { place.sectionId = nil }
                } else {
                    place = .init()
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Runs beside the project load and never holds up posting. A name the user has typed stays.
    private func summarize() async {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.availability == .available else { return }
        summarizing = true
        defer { summarizing = false }
        let model = LanguageModelSession(instructions: TaskTitle.instructions)
        guard let reply = try? await model.respond(to: taskTitle.prompt).content,
              let summarized = taskTitle.summarized(reply),
              name == taskTitle.placeholder
        else { return }
        name = summarized
        #endif
    }

    private func post() {
        posting = true
        postError = nil
        let items = session.items
        let place = place
        let project = place.projectId.flatMap { id in projects.first { $0.id == id } }
        let section = project?.sections.first { $0.id == place.sectionId }
        let title = title
        let report = Data(session.compactJSON.utf8)
        let image = AnnotatedImage.render(session.capture, session.annotations).cgImage
        Task {
            do {
                guard let image else { throw Procrastimate.Failure.imageTooLarge }
                let client = try Procrastimate.Client()
                let encoded = try await Task.detached(priority: .userInitiated) { try Procrastimate.TaskImage(image) }.value
                let id = try await client.post(title: title, place: place, image: encoded, report: report)
                Procrastimate.lastProject = project?.id
                session.shared.formUnion(items)
                let destination = [project?.name ?? "Inbox", section?.name].compactMap { $0 }.joined(separator: " / ")
                // ProcrastiMate opens `procrastimate://task/<id>` on the task, as it does Notouroboros's links.
                session.toast = Toast(text: "Added to \(destination) in ProcrastiMate", link: URL(string: "procrastimate://task/\(id)"))
                close()
            } catch {
                postError = error.localizedDescription
                posting = false
            }
        }
    }
}
#endif
