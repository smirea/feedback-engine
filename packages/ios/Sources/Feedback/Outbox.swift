#if canImport(UIKit)
import Foundation
import Network
import Observation
import UIKit

/// A ProcrastiMate post waiting to land. Its folder holds the bytes: `full.jpg`, `thumb.jpg`, and
/// `feedback.json`.
struct PendingPost: Codable, Identifiable, Equatable, Sendable {
    /// The task's own id, made here, so every retry names the same task.
    let id: String
    /// The name the task is created with: the placeholder or what the user typed.
    let title: String
    /// Sent while `title` is the placeholder, so ProcrastiMate's server names the task from the items.
    let naming: TaskTitle?
    let place: Procrastimate.Place
    /// The project and section names, for the toast and the list.
    let destination: String
    let image: Procrastimate.Attachment
    let report: Procrastimate.Attachment
    let createdAt: Date
    /// Facts about the capture that go into a failure's details.
    let context: [Problem.Fact]
    /// The image sizes and the report the server already stored.
    var uploaded: Set<String> = []
    var attempts = 0
    /// The last attempt's failure.
    var problem: Problem?
}

/// Keeps ProcrastiMate posts on disk until they land, so a post made with a poor connection or none
/// is sent later instead of lost. Every request is idempotent: the server keeps the first bytes for
/// an image id, and a task create with a known id returns that task. A post therefore retries from
/// wherever it stopped. It sends on enqueue, at launch, when the app becomes active, when the network
/// comes back, and on a backoff. A failure a retry
/// cannot fix waits for **Retry** in the sheet.
@MainActor @Observable
final class Outbox {
    static let shared = Outbox()

    enum Event {
        case sent(PendingPost)
        case waiting(PendingPost)
        case failed(PendingPost)
    }

    private(set) var posts: [PendingPost] = []
    /// The post being sent, and what it is doing.
    private(set) var sending: (id: String, step: String)?
    /// Told about each post's outcome while the editor is open, for its toast.
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var draining = false
    /// A drain asked for while one runs, such as the network coming back mid-send.
    @ObservationIgnored private var again = false
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var background = UIBackgroundTaskIdentifier.invalid
    @ObservationIgnored private let monitor = NWPathMonitor()

    private let directory = URL.applicationSupportDirectory.appending(path: "Feedback/Outbox", directoryHint: .isDirectory)

    func start() {
        guard !started else { return }
        started = true
        posts = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .compactMap { try? JSONDecoder().decode(PendingPost.self, from: Data(contentsOf: $0.appending(path: "post.json"))) }
            .sorted { $0.createdAt < $1.createdAt } ?? []
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Outbox.shared.drain() }
        }
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in Outbox.shared.drain() }
        }
        monitor.start(queue: .main)
        drain()
    }

    func add(_ post: PendingPost, full: Data, thumb: Data, report: Data) throws {
        start()
        let folder = folder(post.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try full.write(to: folder.appending(path: "full.jpg"))
        try thumb.write(to: folder.appending(path: "thumb.jpg"))
        try report.write(to: folder.appending(path: "feedback.json"))
        try save(post)
        posts.append(post)
        drain()
    }

    func retryNow(_ id: String) {
        update(id) { $0.problem = nil }
        drain()
    }

    func discard(_ id: String) {
        posts.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// Sends the posts in order. A failure a retry can fix stops the run, since the next post would
    /// meet the same connection; one it cannot fix waits for **Retry** while the rest go on.
    func drain() {
        guard started else { return }
        guard !draining else {
            again = true
            return
        }
        draining = true
        retry?.cancel()
        // Out of background time, the request in flight is cancelled and kept for the next run.
        background = UIApplication.shared.beginBackgroundTask(withName: "Feedback outbox") {
            MainActor.assumeIsolated {
                Outbox.shared.run?.cancel()
                Outbox.shared.endBackground()
            }
        }
        run = Task {
            defer {
                draining = false
                sending = nil
                endBackground()
                if again {
                    again = false
                    drain()
                }
            }
            // Reads `posts` on every turn, so a post added while one is sending goes in this run.
            var tried: Set<String> = []
            while !Task.isCancelled, let post = posts.first(where: { !tried.contains($0.id) && $0.problem?.retryable != false }) {
                tried.insert(post.id)
                guard let problem = await send(post), problem.retryable else { continue }
                again = false
                let attempts = posts.first { $0.id == post.id }?.attempts ?? 1
                // 30 s, 1, 2, 4, 8 minutes, then every 15. Launch, foreground, and a returning
                // network retry sooner.
                let delay = min(30 * pow(2, Double(attempts - 1)), 900)
                retry = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.drain()
                }
                return
            }
        }
    }

    private func endBackground() {
        guard background != .invalid else { return }
        UIApplication.shared.endBackgroundTask(background)
        background = .invalid
    }

    /// Returns the failure, or nil when nothing failed. The post leaves the outbox once its task exists.
    private func send(_ post: PendingPost) async -> Problem? {
        let started = Date.now
        var step = "Reading ProcrastiMate's session"
        sending = (post.id, step)
        do {
            try await create(post, client: Procrastimate.Client(), step: &step)
            onEvent?(.sent(post))
            discard(post.id)
            return nil
        } catch let problem as Problem where problem.status == 410 {
            // An earlier attempt made the task, and it was deleted before this retry heard back.
            discard(post.id)
            return nil
        } catch {
            let attempt = (posts.first { $0.id == post.id }?.attempts ?? 0) + 1
            let problem = Problem(error).with(
                before: [
                    .init(label: "Step", value: step),
                    .init(label: "Attempt", value: "\(attempt), \(String(format: "%.1f", Date.now.timeIntervalSince(started))) s"),
                ],
                after: [
                    .init(label: "Server", value: (try? Procrastimate.Client().apiURL.absoluteString) ?? "not signed in"),
                    .init(label: "Queued", value: post.createdAt.formatted(.iso8601)),
                ] + post.context
            )
            update(post.id) {
                $0.attempts = attempt
                $0.problem = problem
            }
            if let failed = posts.first(where: { $0.id == post.id }) {
                onEvent?(problem.retryable ? .waiting(failed) : .failed(failed))
            }
            return problem
        }
    }

    /// Uploads what the server does not have yet, then creates the task.
    private func create(_ post: PendingPost, client: Procrastimate.Client, step: inout String) async throws {
        let folder = folder(post.id)
        let report = try Data(contentsOf: folder.appending(path: "feedback.json"))
        let uploads: [(key: String, id: String, name: String, type: String, file: (name: String, type: String)?, data: () throws -> Data)] = [
            (key: "full", id: post.image.id, name: "the image", type: "image/jpeg", file: nil, data: { try Data(contentsOf: folder.appending(path: "full.jpg")) }),
            (key: "thumb", id: post.image.id, name: "the thumbnail", type: "image/jpeg", file: nil, data: { try Data(contentsOf: folder.appending(path: "thumb.jpg")) }),
            (key: "file", id: post.report.id, name: "feedback.json", type: "application/octet-stream", file: (post.report.name ?? "feedback.json", post.report.type ?? "application/json"), data: { report }),
        ]
        for upload in uploads where !(posts.first { $0.id == post.id }?.uploaded.contains("\(upload.id)/\(upload.key)") ?? false) {
            step = "Uploading \(upload.name)"
            sending = (post.id, step)
            try await client.put(id: upload.id, key: upload.key, data: upload.data(), type: upload.type, file: upload.file)
            update(post.id) { $0.uploaded.insert("\(upload.id)/\(upload.key)") }
        }
        step = "Creating the task"
        sending = (post.id, step)
        try await client.create(id: post.id, title: post.title, suggestion: post.naming, place: post.place, attachments: [post.image, post.report])
    }

    private func update(_ id: String, _ change: (inout PendingPost) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        change(&posts[index])
        try? save(posts[index])
    }

    private func save(_ post: PendingPost) throws {
        try JSONEncoder().encode(post).write(to: folder(post.id).appending(path: "post.json"), options: .atomic)
    }

    private func folder(_ id: String) -> URL { directory.appending(path: id, directoryHint: .isDirectory) }
}
#endif
