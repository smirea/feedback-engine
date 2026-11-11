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
    /// The name the task should have: the placeholder, the model's summary once it answers, or what
    /// the user typed.
    var title: String
    /// What the model is summarizing, while it is. Kept so a relaunch can ask again.
    var naming: TaskTitle?
    /// The name the server has, once the task exists. A summary that arrives later renames it.
    var sentTitle: String?
    let place: Procrastimate.Place
    /// The project and section names, for the toast and the list.
    let destination: String
    let image: Procrastimate.Attachment
    let report: Procrastimate.Attachment
    let createdAt: Date
    /// Facts about the capture that go into a failure's details.
    let context: [Problem.Fact]
    /// The image sizes and report parts the server already stored.
    var uploaded: Set<String> = []
    var attempts = 0
    /// The last attempt's failure.
    var problem: Problem?
}

/// Keeps ProcrastiMate posts on disk until they land, so a post made with a poor connection or none
/// is sent later instead of lost. Every request is idempotent: the server keeps the first bytes for
/// an image id, a task create with a known id returns that task, and a rename sets a name. A post
/// therefore retries from wherever it stopped. It sends on enqueue, at launch, when the app becomes
/// active, when the network comes back, when the model names it, and on a backoff. A failure a retry
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
    /// A drain asked for while one runs, such as a name arriving mid-send.
    @ObservationIgnored private var again = false
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var run: Task<Void, Never>?
    @ObservationIgnored private var background = UIBackgroundTaskIdentifier.invalid
    @ObservationIgnored private let monitor = NWPathMonitor()

    private let directory = URL.applicationSupportDirectory.appending(path: "Feedback/Outbox", directoryHint: .isDirectory)

    /// Posts still on their way, as the sheet lists them. One whose task exists and only waits for a
    /// name is done as far as the user can tell.
    var unsent: [PendingPost] { posts.filter { $0.sentTitle == nil } }

    func start() {
        guard !started else { return }
        started = true
        posts = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .compactMap { try? JSONDecoder().decode(PendingPost.self, from: Data(contentsOf: $0.appending(path: "post.json"))) }
            .sorted { $0.createdAt < $1.createdAt } ?? []
        for post in posts {
            guard let naming = post.naming else { continue }
            // Once the task exists, a rename this late could undo one made in ProcrastiMate meanwhile.
            if post.sentTitle == nil, let summary = naming.summary() {
                name(post.id, with: summary)
            } else {
                update(post.id) { $0.naming = nil }
            }
        }
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

    /// Gives a post the model's name when it answers. Before the task exists the post goes out under
    /// it; after, the task is renamed. Without an answer the placeholder stays.
    func name(_ id: String, with summary: Task<String?, Never>) {
        Task {
            let summarized = await summary.value
            update(id) { post in
                post.naming = nil
                if let summarized { post.title = summarized }
            }
            drain()
        }
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

    /// Returns the failure, or nil when nothing failed. The post leaves the outbox once its task
    /// exists under its final name; until the model answers, it waits.
    private func send(_ post: PendingPost) async -> Problem? {
        let started = Date.now
        var step = "Reading ProcrastiMate's session"
        sending = (post.id, step)
        do {
            let client = try Procrastimate.Client()
            if post.sentTitle == nil {
                try await create(post, client: client, step: &step)
                onEvent?(.sent(post))
            }
            guard let current = posts.first(where: { $0.id == post.id }), current.naming == nil else { return nil }
            if current.title != current.sentTitle {
                step = "Renaming the task"
                sending = (post.id, step)
                do {
                    try await client.rename(id: post.id, title: current.title)
                } catch let problem as Problem where !problem.retryable {
                    // Deleted or refused: the name was a nicety, and the task is there.
                }
            }
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

    /// Uploads what the server does not have yet, then creates the task under the name as of now, so
    /// a summary that arrived during the uploads goes out with it.
    private func create(_ post: PendingPost, client: Procrastimate.Client, step: inout String) async throws {
        let folder = folder(post.id)
        let report = try Data(contentsOf: folder.appending(path: "feedback.json"))
        var uploads = [
            (key: "full", id: post.image.id, name: "the image", type: "image/jpeg", data: { try Data(contentsOf: folder.appending(path: "full.jpg")) }),
            (key: "thumb", id: post.image.id, name: "the thumbnail", type: "image/jpeg", data: { try Data(contentsOf: folder.appending(path: "thumb.jpg")) }),
        ]
        // ProcrastiMate stores a file in parts that each fit one database row.
        let starts = Array(stride(from: 0, to: report.count, by: Procrastimate.filePartBytes))
        for (index, start) in starts.enumerated() {
            let name = starts.count == 1 ? "feedback.json" : "feedback.json, part \(index + 1) of \(starts.count)"
            uploads.append((key: "part\(index)", id: post.report.id, name: name, type: "application/octet-stream", data: {
                report.subdata(in: start..<min(start + Procrastimate.filePartBytes, report.count))
            }))
        }
        for upload in uploads where !(posts.first { $0.id == post.id }?.uploaded.contains("\(upload.id)/\(upload.key)") ?? false) {
            step = "Uploading \(upload.name)"
            sending = (post.id, step)
            try await client.put(id: upload.id, key: upload.key, data: upload.data(), type: upload.type)
            update(post.id) { $0.uploaded.insert("\(upload.id)/\(upload.key)") }
        }
        step = "Creating the task"
        sending = (post.id, step)
        let title = posts.first { $0.id == post.id }?.title ?? post.title
        try await client.create(id: post.id, title: title, place: post.place, attachments: [post.image, post.report])
        update(post.id) { $0.sentTitle = title }
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
