import Foundation

/// One line of the hub's NDJSON stream.
struct HubEvent: Codable, Sendable, Equatable {
    var heard: String?
    var state: String?
    var tool: String?
    var text: String?
    var message: String?
    /// `state: "approval"`: id of the pending request, and what it wants to run
    var id: String?
    var summary: String?
    /// Decision for a pending request: `{"approval": id, "allowed": Bool}`
    var approval: String?
    var allowed: Bool?
}

/// A gated tool call waiting for Approve / Deny (the hub denies it after 60 s).
struct Approval: Identifiable, Equatable, Sendable {
    let id: String
    let tool: String
    let summary: String
    let since: Date

    init?(_ event: HubEvent, since: Date = .now) {
        guard event.state == "approval", let id = event.id else { return nil }
        self.id = id
        self.tool = event.tool ?? "Tool"
        self.summary = event.summary ?? ""
        self.since = since
    }

    init(id: String, tool: String, summary: String, since: Date = .now) {
        self.id = id; self.tool = tool; self.summary = summary; self.since = since
    }

    static let timeout: TimeInterval = 60
}

/// One finished turn from `GET /history`.
struct HistoryTurn: Decodable, Sendable, Equatable {
    var at: String
    var heard: String?
    var reply: String?
    var ok: Bool?

    var date: Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(at))
            ?? (try? Date.ISO8601FormatStyle().parse(at))
    }
}
