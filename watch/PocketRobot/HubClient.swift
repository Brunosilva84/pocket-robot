import Foundation

/// One line of the hub's NDJSON stream.
struct HubEvent: Decodable, Sendable, Equatable {
    var heard: String?
    var state: String?
    var tool: String?
    var text: String?
    var message: String?
}

enum HubError: Error, Equatable {
    case badURL
    case unauthorized
    case busy
    case http(Int)
    case unreachable
}

enum HealthResult: Sendable, Equatable {
    case ok
    case unauthorized
    case unreachable
}

struct HubClient: Sendable {
    let baseURL: URL?
    let token: String

    init(baseURL: String = Config.hubURL, token: String = Config.token) {
        self.baseURL = URL(string: baseURL)
        self.token = token
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

    /// Sends the recording and calls `onEvent` for every NDJSON line until the stream ends.
    func talk(audio: URL, onEvent: @MainActor @Sendable (HubEvent) -> Void) async throws {
        var req = try request("talk")
        req.httpMethod = "POST"
        req.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: audio)

        let bytes: URLSession.AsyncBytes, response: URLResponse
        do {
            (bytes, response) = try await Self.session.bytes(for: req)
        } catch {
            throw HubError.unreachable
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401, 403: throw HubError.unauthorized
        case 409: throw HubError.busy
        case let code: throw HubError.http(code)
        }
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
}
