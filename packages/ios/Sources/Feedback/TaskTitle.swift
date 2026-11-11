import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A ProcrastiMate task's name: `<screen> Feedback: N changes` at first, then
/// `N <screen> Feedback: <summary>` once the on-device model has summarized the items.
struct TaskTitle: Codable, Equatable, Sendable {
    let subject: String
    let count: Int
    let prompt: String

    init(_ capture: Capture, items: [FeedbackItem]) {
        subject = [capture.screenName ?? capture.environment.first { $0.name == "App" }?.value, "Feedback"].compactMap { $0 }.joined(separator: " ")
        count = items.count
        prompt = items.map { item in
            let target = capture.nodes[item.target]
            return "- On \(target.title): \(item.text.split(whereSeparator: \.isNewline).joined(separator: " "))"
        }.joined(separator: "\n")
    }

    static let instructions = """
        You name tasks for a developer. Given feedback items about an app screen, reply with one \
        lowercase phrase of at most 8 words that covers every item, such as "bigger titles, \
        remove the share button". No quotes, no trailing period, no preamble.
        """

    var placeholder: String { "\(subject): \(count) \(count == 1 ? "change" : "changes")" }

    /// The model's reply on one line without the wrapping it sometimes adds. `nil` when nothing
    /// is left, so the placeholder stays.
    func summarized(_ reply: String) -> String? {
        let line = reply.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let summary = line
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’`*")))
            .trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespaces))
        return summary.isEmpty ? nil : "\(count) \(subject): \(summary)"
    }

    /// The on-device model's name, or nil without Apple Intelligence or a usable reply. A task of its
    /// own, so a sheet that closes before the model answers hands it to the outbox instead of losing it.
    func summary() -> Task<String?, Never>? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, macOS 26, *), SystemLanguageModel.default.availability == .available else { return nil }
        return Task.detached(priority: .userInitiated) {
            let model = LanguageModelSession(instructions: TaskTitle.instructions)
            guard let reply = try? await model.respond(to: prompt).content else { return nil }
            return summarized(reply)
        }
        #else
        return nil
        #endif
    }
}
