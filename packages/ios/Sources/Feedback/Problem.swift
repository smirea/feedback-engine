import Foundation

/// A failure the editor shows: one line to read, and facts to expand and copy, so a post that fails
/// on the phone can be diagnosed without reproducing it.
struct Problem: LocalizedError, Sendable, Equatable, Codable {
    struct Fact: Sendable, Equatable, Codable {
        let label: String
        let value: String
    }

    let message: String
    let facts: [Fact]
    /// Whether trying again later can fix it: no connection, a timeout, a server error, or a
    /// session that ProcrastiMate may renew once it is opened.
    let retryable: Bool

    init(message: String, facts: [Fact] = [], retryable: Bool = false) {
        self.message = message
        self.facts = facts
        self.retryable = retryable
    }

    /// Keeps a `Problem`'s own facts. Any other error gets its full description, which for an
    /// `NSError` carries the domain, code, and user info, such as the underlying network error.
    init(_ error: any Error) {
        if let problem = error as? Problem {
            self = problem
        } else {
            self.init(message: error.localizedDescription, facts: [Fact(label: "Error", value: String(reflecting: error))], retryable: error is URLError)
        }
    }

    /// A request that got no answer, or one it could not use. The response body is cut at 2,000
    /// characters: a proxy's HTML error page says what it needs to in its first lines.
    static func request(_ method: String, _ url: URL, status: Int?, body: Data?, error: any Error) -> Problem {
        var facts = [Fact(label: "Request", value: "\(method) \(url.absoluteString)")]
        if let status { facts.append(Fact(label: "Status", value: String(status))) }
        if let body, !body.isEmpty {
            let text = String(decoding: body, as: UTF8.self)
            facts.append(Fact(label: "Response", value: text.count > 2000 ? "\(text.prefix(2000))…" : text))
        }
        facts.append(Fact(label: "Error", value: String(reflecting: error)))
        let retryable = status.map { $0 == 401 || $0 == 408 || $0 == 429 || $0 >= 500 } ?? (error is URLError)
        return Problem(message: error.localizedDescription, facts: facts, retryable: retryable)
    }

    /// `before` and `after` around the problem's own facts.
    func with(before: [Fact] = [], after: [Fact] = []) -> Problem {
        Problem(message: message, facts: before + facts + after, retryable: retryable)
    }

    var errorDescription: String? { message }

    var details: String {
        facts.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    /// What Copy puts on the pasteboard.
    var text: String {
        facts.isEmpty ? message : "\(message)\n\n\(details)"
    }
}
