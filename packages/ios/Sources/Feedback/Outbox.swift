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
    let title: String
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
/// an image id, and a task create with a known id returns that task. A post therefore retries from
/// wherever it stopped. It sends on enqueue, at launch, when the app becomes active, when the network
/// comes back, and on a backoff. A failure a retry cannot fix waits for **Retry** in the sheet.
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
    @ObservationIgnored private var retry: Task<Void, Never>?
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
        guard started, !draining else { return }
        draining = true
        retry?.cancel()
        let background = UIApplication.shared.beginBackgroundTask(withName: "Feedback outbox")
        Task {
            defer {
                draining = false
                sending = nil
                UIApplication.shared.endBackgroundTask(background)
            }
            // Reads `posts` on every turn, so a post added while one is sending goes in this run.
            var tried: Set<String> = []
            while let post = posts.first(where: { !tried.contains($0.id) && $0.problem?.retryable != false }) {
                tried.insert(post.id)
                guard let problem = await send(post), problem.retryable else { continue }
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

    /// Returns the failure, or nil once the post landed and left the outbox.
    private func send(_ post: PendingPost) async -> Problem? {
        let started = Date.now
        var step = "Reading ProcrastiMate's session"
        sending = (post.id, step)
        let folder = folder(post.id)
        do {
            let client = try Procrastimate.Client()
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
            try await client.create(id: post.id, title: post.title, place: post.place, attachments: [post.image, post.report])
            discard(post.id)
            onEvent?(.sent(post))
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
