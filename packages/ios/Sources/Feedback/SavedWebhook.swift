import CoreGraphics
import Foundation
import Observation

/// UIKit sets no PNG compression, so only a JPEG has a level.
enum ImageEncoding: Codable, Hashable, Sendable {
    case png
    case jpeg(Compression)

    enum Compression: String, Codable, CaseIterable, Sendable {
        case low, medium, high

        /// The same qualities as the web's.
        var quality: CGFloat {
            switch self {
            case .low: 0.9
            case .medium: 0.7
            case .high: 0.5
            }
        }
    }
}

/// A webhook someone added in the editor. The app keeps it, and the Share menu lists it after the
/// app's own.
struct SavedWebhook: Codable, Hashable, Identifiable, Sendable {
    struct Header: Codable, Hashable, Sendable {
        var name: String
        var value: String
    }

    var id: String
    var name: String
    var url: URL
    var header: Header?
    var image: ImageEncoding?
    var feedback: Bool

    var webhook: FeedbackWebhook {
        FeedbackWebhook(name: name, url: url, headers: header.map { [$0.name: $0.value] } ?? [:])
    }

    var contents: WebhookContents { .saved(image: image, feedback: feedback) }
}

struct WebhookDraft: Equatable {
    enum Format: Hashable { case png, jpeg }

    struct Errors: Equatable {
        var name: String?
        var url: String?
        var header: String?
    }

    var name = ""
    var url = ""
    var header = ""
    var image = true
    var format = Format.png
    var compression = ImageEncoding.Compression.medium
    var feedback = true

    init() {}

    init(_ webhook: SavedWebhook) {
        name = webhook.name
        url = webhook.url.absoluteString
        header = webhook.header.map { "\($0.name): \($0.value)" } ?? ""
        image = webhook.image != nil
        if case .jpeg(let level) = webhook.image {
            format = .jpeg
            compression = level
        }
        feedback = webhook.feedback
    }

    private static let token = Set("!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    /// The webhook the draft describes, or what is wrong with it. `taken` holds the names of the
    /// Share menu's other entries, since a name is what `Feedback.pinned` picks an entry by.
    func read(id: String, taken: [String]) -> Result<SavedWebhook, Errors> {
        var errors = Errors()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errors.name = "Give the webhook a name."
        } else if taken.contains(where: { $0.lowercased() == name.lowercased() }) {
            errors.name = "The Share menu already has \(name)."
        }
        let url = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))
        if url?.host() == nil || !["http", "https"].contains(url?.scheme?.lowercased()) {
            errors.url = "Enter an address that starts with http:// or https://."
        }
        let line = header.trimmingCharacters(in: .whitespacesAndNewlines)
        var header: SavedWebhook.Header?
        if !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1)
            let field = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            let value = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            if parts.count == 2, !field.isEmpty, field.allSatisfy(Self.token.contains), !value.isEmpty {
                header = .init(name: field, value: value)
            } else {
                errors.header = "Write the header as Name: value, such as Authorization: Bearer key."
            }
        }
        guard errors == Errors(), let url else { return .failure(errors) }
        return .success(SavedWebhook(
            id: id,
            name: name,
            url: url,
            header: header,
            image: image ? (format == .jpeg ? .jpeg(compression) : .png) : nil,
            feedback: feedback
        ))
    }

    var note: String {
        let parts = ["the title", feedback ? "the feedback JSON" : nil, image ? "the image" : nil, "the device JSON"].compactMap { $0 }
        return "Each post sends \(parts.dropLast().joined(separator: ", ")), and \(parts.last!)."
    }
}

extension WebhookDraft.Errors: Error {}

/// The webhooks saved in the editor, which the app keeps in its `UserDefaults`.
@MainActor @Observable
final class SavedWebhooks {
    static let shared = SavedWebhooks(defaults: .standard)

    private static let key = "feedback.webhooks.v1"
    private let defaults: UserDefaults
    private(set) var all: [SavedWebhook]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        all = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([SavedWebhook].self, from: $0) } ?? []
    }

    func save(_ webhook: SavedWebhook) {
        if let index = all.firstIndex(where: { $0.id == webhook.id }) { all[index] = webhook } else { all.append(webhook) }
        store()
    }

    func delete(id: String) {
        all.removeAll { $0.id == id }
        store()
    }

    private func store() {
        defaults.set(try? JSONEncoder().encode(all), forKey: Self.key)
    }
}
