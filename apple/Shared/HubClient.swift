import Foundation

enum HubError: Error, Equatable {
    case badURL
    case unauthorized
    case busy
    case notFound
    case http(Int)
    case unreachable
}

enum HealthResult: Sendable, Equatable {
    case ok
    case unauthorized
    case unreachable
}

/// What a turn sends: a recording (m4a) or a typed prompt.
enum TalkBody: Sendable {
    case audio(Data)
    case text(String)
}

struct HubClient: Sendable {
    let baseURL: URL?
    let token: String

    init(_ settings: HubSettings = .current) {
        self.baseURL = URL(string: settings.url)
        self.token = settings.token
    }

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120 // idle time between stream lines
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private func request(_ path: String) throws -> URLRequest {
        guard let url = baseURL?.appending(path: path) else { throw HubError.badURL }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    func health() async -> HealthResult {
        guard var req = try? request("health") else { return .unreachable }
        req.timeoutInterval = 5
        do {
            let (_, response) = try await Self.session.data(for: req)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: return .ok
            case 401, 403: return .unauthorized
            default: return .unreachable
            }
        } catch {
            return .unreachable
        }
    }

    /// Sends the recording or text and calls `onEvent` for every NDJSON line until the stream ends.
    func talk(_ body: TalkBody, onEvent: @MainActor @Sendable (HubEvent) -> Void) async throws {
        var req = try request("talk")
        req.httpMethod = "POST"
        switch body {
        case .audio(let data):
            req.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
            req.httpBody = data
        case .text(let text):
            req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = Data(text.utf8)
        }

        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await Self.session.bytes(for: req)
        } catch {
            throw HubError.unreachable
        }
        try Self.check(response)
        let decoder = JSONDecoder()
        do {
            for try await line in bytes.lines {
                guard let data = line.data(using: .utf8), !line.isEmpty,
                      let event = try? decoder.decode(HubEvent.self, from: data) else { continue }
                await onEvent(event)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw HubError.unreachable
        }
    }

    /// Answers a pending approval. `HubError.notFound` when it was already decided or timed out.
    func approve(id: String, allow: Bool) async throws {
        var req = try request("approve")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": id, "allow": allow])
        try await send(req)
    }

    /// Finished turns, newest last.
    func history() async throws -> [HistoryTurn] {
        struct Body: Decodable { var turns: [HistoryTurn] }
        let data = try await send(try request("history"))
        return try JSONDecoder().decode(Body.self, from: data).turns
    }

    /// Forgets the Claude session; the next turn starts a new conversation.
    func newConversation() async throws {
        var req = try request("new")
        req.httpMethod = "POST"
        try await send(req)
    }

    @discardableResult
    private func send(_ req: URLRequest) async throws -> Data {
        var req = req
        req.timeoutInterval = 10
        let data: Data, response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: req)
        } catch {
            throw HubError.unreachable
        }
        try Self.check(response)
        return data
    }

    private static func check(_ response: URLResponse) throws {
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return
        case 401, 403: throw HubError.unauthorized
        case 404: throw HubError.notFound
        case 409: throw HubError.busy
        case let code: throw HubError.http(code)
        }
    }
}
