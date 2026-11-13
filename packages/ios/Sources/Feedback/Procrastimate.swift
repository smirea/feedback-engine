#if canImport(UIKit)
import ImageIO
import Security
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    /// An image is `{id, width, height}` and a file `{id, name, type, bytes}`; the server tells them apart by shape.
    struct Attachment: Codable, Hashable, Sendable {
        let id: String
        var width: Int?
        var height: Int?
        var name: String?
        var type: String?
        var bytes: Int?
    }

    /// Where a task goes: the Inbox when `projectId` is nil, and the project's top, above its
    /// sections, when `sectionId` is.
    struct Place: Codable, Hashable, Sendable {
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

        /// Stores one image size or file part. ProcrastiMate keeps the first bytes stored under an
        /// id, so sending them again is safe.
        func put(id: String, key: String, data: Data, type: String) async throws {
            _ = try await send("PUT", "api/images", query: ["id": id, "size": key], body: data, type: type)
        }

        /// Creates the task with its attachments in one write. The id is the client's, so a retry
        /// whose first answer was lost returns that task instead of adding a second one. Returns the
        /// task's title, which is the first attempt's for such a retry, not this one's.
        func create(id: String, title: String, place: Place, attachments: [Attachment]) async throws -> String {
            struct NewTask: Encodable { let id: String; let title: String; let projectId: String?; let sectionId: String?; let attachments: [Attachment] }
            struct Task: Decodable { let id: String; let title: String }
            let task: Task = try decode(await send("POST", "api/tasks", json: NewTask(id: id, title: title, projectId: place.projectId, sectionId: place.sectionId, attachments: attachments)))
            guard task.id == id else {
                throw Problem(message: "ProcrastiMate made a task under another id, so a retry would add a second one.", facts: [.init(label: "Task", value: "\(task.id), sent \(id)")])
            }
            return task.title
        }

        func rename(id: String, title: String) async throws {
            struct Edit: Encodable { let title: String }
            _ = try await send("PATCH", "api/tasks", query: ["id": id], json: Edit(title: title))
        }

        private func send(_ method: String, _ path: String, query: [String: String] = [:], json: some Encodable) async throws -> Data {
            try await send(method, path, query: query, body: JSONEncoder().encode(json), type: "application/json")
        }

        private func send(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil, type: String? = nil) async throws -> Data {
            var url = apiURL.appending(path: path)
            if !query.isEmpty { url.append(queryItems: query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }) }
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = method
            request.httpBody = body
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("Feedback", forHTTPHeaderField: "User-Agent")
            if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw Problem.request(method, url, status: nil, body: nil, error: error)
            }
            guard let status = (response as? HTTPURLResponse)?.statusCode else {
                throw Problem.request(method, url, status: nil, body: data, error: Failure.unreadable)
            }
            if status == 401 { throw Problem.request(method, url, status: status, body: data, error: Failure.signedOut) }
            guard (200..<300).contains(status) else {
                struct Body: Decodable { let message: String? }
                let message = (try? JSONDecoder().decode(Body.self, from: data))?.message
                throw Problem.request(method, url, status: status, body: data, error: Failure.server(status: status, message: message))
            }
            return data
        }

        private func decode<T: Decodable>(_ data: Data) throws -> T {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw Problem(message: Failure.unreadable.localizedDescription, facts: [
                    Problem.Fact(label: "Response", value: String(decoding: data.prefix(2000), as: UTF8.self)),
                    Problem.Fact(label: "Error", value: String(reflecting: error)),
                ])
            }
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

/// Picks the project and the task's name, then hands the post to the outbox and closes.
struct ProcrastimateSheet: View {
    let session: Session
    let close: () -> Void
    @State private var projects = Procrastimate.cachedProjects
    @State private var place = Procrastimate.Place(projectId: Procrastimate.lastProject)
    @State private var name: String
    @State private var loading = true
    @State private var loadProblem: Problem?
    @State private var saveProblem: Problem?
    @State private var saving = false
    @State private var summarizing = false
    /// The model's work, which outlives the sheet once **Add** hands it to the outbox.
    @State private var summary: Task<String?, Never>?
    @State private var handedOff = false
    private let outbox = Outbox.shared
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
            ScrollViewReader { scroll in
                Form {
                    // Above the project list, which can be longer than the sheet: an error under it
                    // went unseen, and a failed post looked like a spinner that stopped.
                    Group {
                        if let saveProblem { ProblemSection(problem: saveProblem) }
                        if let loadProblem { ProblemSection(problem: loadProblem) }
                        ForEach(outbox.unsent) { post in
                            PendingSection(post: post, step: outbox.sending?.id == post.id ? outbox.sending?.step : nil)
                        }
                    }
                    .id("status")
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
                    }
                }
                .onChange(of: saveProblem) {
                    guard let saveProblem else { return }
                    withAnimation { scroll.scrollTo("status", anchor: .top) }
                    UIAccessibility.post(notification: .announcement, argument: saveProblem.message)
                }
            }
            .navigationTitle("Add to ProcrastiMate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Add", action: save).disabled(title.isEmpty)
                    }
                }
            }
            .disabled(saving)
        }
        .dynamicTypeSize(...EditorView.largestTextSize)
        .interactiveDismissDisabled(saving)
        .task { await load() }
        .task { await summarize() }
        .onDisappear { if !handedOff { summary?.cancel() } }
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
            let problem = Problem(error)
            // Offline, the cached projects are enough to post, and the outbox sends later.
            guard !problem.retryable || projects.isEmpty else { return }
            loadProblem = problem.with(before: [.init(label: "Step", value: "Loading the projects")], after: environment)
        }
    }

    /// Runs beside the project load and never holds up posting. A name the user has typed stays.
    private func summarize() async {
        guard let task = taskTitle.summary() else { return }
        summary = task
        summarizing = true
        let summarized = await task.value
        summarizing = false
        if let summarized, name == taskTitle.placeholder { name = summarized }
    }

    private var environment: [Problem.Fact] {
        session.capture.environment.map { Problem.Fact(label: $0.name, value: $0.value) }
    }

    /// Everything that needs no connection: the session, the image, and the files on disk. The
    /// outbox does the rest, so the sheet closes at once even offline.
    private func save() {
        saving = true
        saveProblem = nil
        let items = session.items
        let place = place
        let project = place.projectId.flatMap { id in projects.first { $0.id == id } }
        let section = project?.sections.first { $0.id == place.sectionId }
        let destination = [project?.name ?? "Inbox", section?.name].compactMap { $0 }.joined(separator: " / ")
        let title = title
        // Added before the model answered and under its placeholder: the outbox waits for the answer.
        let naming = summarizing && title == taskTitle.placeholder ? summary : nil
        let report = Data(session.compactJSON.utf8)
        let environment = environment
        let image = AnnotatedImage.render(session.capture, session.annotations).cgImage
        Task {
            var step = "Reading ProcrastiMate's session"
            do {
                _ = try Procrastimate.Client()
                guard report.count <= Procrastimate.fileMaxBytes else { throw Procrastimate.Failure.reportTooLarge }
                guard let image else { throw Procrastimate.Failure.imageTooLarge }
                step = "Encoding the image"
                let encoded = try await Task.detached(priority: .userInitiated) { try Procrastimate.TaskImage(image) }.value
                step = "Saving to the outbox"
                let post = PendingPost(
                    id: UUID().uuidString.lowercased(),
                    title: title,
                    naming: naming == nil ? nil : taskTitle,
                    place: place,
                    destination: destination,
                    image: .init(id: encoded.id, width: encoded.width, height: encoded.height),
                    report: .init(id: UUID().uuidString.lowercased(), name: "feedback.json", type: "application/json", bytes: report.count),
                    createdAt: .now,
                    context: [
                        .init(label: "Place", value: [project.map { "\($0.name) (\($0.id))" } ?? "Inbox", section.map { "\($0.name) (\($0.id))" }].compactMap { $0 }.joined(separator: " / ")),
                        .init(label: "Image", value: "\(image.width) × \(image.height) px, sent as \(encoded.width) × \(encoded.height) JPEG of \(encoded.full.count) bytes, thumbnail \(encoded.thumb.count) bytes"),
                        .init(label: "Report", value: "\(report.count) bytes"),
                    ] + environment
                )
                try outbox.add(post, full: encoded.full, thumb: encoded.thumb, report: report)
                if let naming {
                    outbox.name(post.id, with: naming)
                    handedOff = true
                }
                Procrastimate.lastProject = project?.id
                session.shared.formUnion(items)
                session.toast = Toast(text: "Sending to \(destination) in ProcrastiMate…")
                close()
            } catch {
                saveProblem = Problem(error).with(before: [.init(label: "Step", value: step)], after: environment)
                saving = false
            }
        }
    }
}

/// A post in the outbox: what it is, where it stands, and its last failure.
private struct PendingSection: View {
    let post: PendingPost
    /// What the outbox is doing with it right now.
    let step: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title).lineLimit(2)
                Text(post.destination).font(.footnote).foregroundStyle(.secondary)
            }
            if let step {
                Label { Text("\(step)…") } icon: { ProgressView() }
            } else if let problem = post.problem {
                ProblemRows(problem: problem)
                if problem.retryable {
                    Label("Sends by itself when it can. Tried \(post.attempts) \(post.attempts == 1 ? "time" : "times").", systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if step == nil {
                Button("Retry Now", systemImage: "arrow.clockwise") { Outbox.shared.retryNow(post.id) }
                Button("Discard", systemImage: "trash", role: .destructive) { Outbox.shared.discard(post.id) }
            }
        } header: {
            Text("Waiting to send")
        }
    }
}

/// A failure on its own, in a section of its own.
private struct ProblemSection: View {
    let problem: Problem

    var body: some View {
        Section { ProblemRows(problem: problem) }
    }
}

/// A failure's message, with its facts under **Details** and a button that copies both.
struct ProblemRows: View {
    let problem: Problem
    @State private var expanded = false
    @State private var copied = false

    var body: some View {
        Label {
            Text(problem.message)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
        if !problem.facts.isEmpty {
            DisclosureGroup("Details", isExpanded: $expanded) {
                Text(problem.details)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        Button(copied ? "Copied" : "Copy Error", systemImage: copied ? "checkmark" : "doc.on.doc") {
            UIPasteboard.general.string = problem.text
            copied = true
        }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
        .onChange(of: problem) { (expanded, copied) = (false, false) }
    }
}
#endif
