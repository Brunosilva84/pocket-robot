import Foundation

/// WatchConnectivity relay messages (watch ⇄ phone), used when the watch can't reach the hub itself.
///
/// - watch → phone: `["talk": Data(m4a)]`, `["approve": id, "allow": Bool]`
/// - phone → watch: `["event": Data(json line)]` per hub event, `["end": true]` when the stream ends,
///   `["error": "unreachable"|"unauthorized"|"busy"]` on failure
enum RelayMessage: Sendable, Equatable {
    case talk(Data)
    case approve(id: String, allow: Bool)
    case event(HubEvent)
    case end
    case error(String)

    init?(_ message: [String: Any]) {
        if let data = message["talk"] as? Data {
            self = .talk(data)
        } else if let id = message["approve"] as? String, let allow = message["allow"] as? Bool {
            self = .approve(id: id, allow: allow)
        } else if let data = message["event"] as? Data, let event = try? JSONDecoder().decode(HubEvent.self, from: data) {
            self = .event(event)
        } else if message["end"] as? Bool == true {
            self = .end
        } else if let error = message["error"] as? String {
            self = .error(error)
        } else {
            return nil
        }
    }

    var message: [String: Any] {
        switch self {
        case .talk(let data): ["talk": data]
        case .approve(let id, let allow): ["approve": id, "allow": allow]
        case .event(let event): ["event": (try? JSONEncoder().encode(event)) ?? Data()]
        case .end: ["end": true]
        case .error(let error): ["error": error]
        }
    }

    /// Relay error string for a hub failure, and back.
    static func errorName(_ error: any Error) -> String {
        switch error as? HubError {
        case .unauthorized: "unauthorized"
        case .busy: "busy"
        default: "unreachable"
        }
    }

    static func hubError(_ name: String) -> HubError {
        switch name {
        case "unauthorized": .unauthorized
        case "busy": .busy
        default: .unreachable
        }
    }

    /// `sendMessage` payloads are capped (~64 KB); longer recordings go with `transferFile` and this metadata.
    static let maxMessageBytes = 60_000
    static var talkFileMetadata: [String: Any] { ["talk": true] }
}
