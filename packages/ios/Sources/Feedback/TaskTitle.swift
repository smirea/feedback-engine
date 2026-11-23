import Foundation

/// A ProcrastiMate task's name, `<screen> Feedback: N changes`. Encoded, it is the `titleSuggestion` a post
/// carries while the name is untouched, from which ProcrastiMate's server renames the task
/// `N <screen> Feedback: <summary>`.
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

    var placeholder: String { "\(subject): \(count) \(count == 1 ? "change" : "changes")" }
}
