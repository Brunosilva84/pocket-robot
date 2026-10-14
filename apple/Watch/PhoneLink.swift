import Foundation
import Synchronization
import WatchConnectivity

/// Watch side of WatchConnectivity: hub settings pushed from the iPhone, and turns relayed through
/// the iPhone when the hub is out of the watch's reach.
@MainActor
final class PhoneLink: NSObject, WCSessionDelegate {
    /// Called after the iPhone sent new hub settings (already stored).
    var onSettings: (() -> Void)?

    /// Messages of the relayed turn in flight, fed straight from the delegate queue (keeps their order).
    private nonisolated let inbox = Mutex<AsyncStream<RelayMessage>.Continuation?>(nil)
    private var lastMessage = Date.now

    var isReachable: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the recording to the iPhone, which runs the turn against the hub and streams the events back.
    func talk(_ audio: Data, onEvent: @MainActor @Sendable (HubEvent) -> Void) async throws {
        let (stream, cont) = AsyncStream.makeStream(of: RelayMessage.self)
        inbox.withLock { $0 = cont }
        lastMessage = .now
        // the iPhone went quiet (out of range, app killed): give up like a dropped hub stream
        let watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, Date.now.timeIntervalSince(self.lastMessage) > 120 else { continue }
                cont.yield(.error("unreachable"))
                return
            }
        }
        defer {
            watchdog.cancel()
            inbox.withLock { $0 = nil }
        }

        if audio.count <= RelayMessage.maxMessageBytes {
            WCSession.default.sendMessage(RelayMessage.talk(audio).message, replyHandler: nil) { _ in
                cont.yield(.error("unreachable"))
            }
        } else {
            let file = FileManager.default.temporaryDirectory.appending(path: "relay-\(UUID().uuidString).m4a")
            try audio.write(to: file)
            WCSession.default.transferFile(file, metadata: RelayMessage.talkFileMetadata)
        }

        for await message in stream {
            lastMessage = .now
            switch message {
            case .event(let event): onEvent(event)
            case .end: return
            case .error(let name): throw RelayMessage.hubError(name)
            case .talk, .approve: break
            }
        }
        throw CancellationError()
    }

    func approve(id: String, allow: Bool) {
        WCSession.default.sendMessage(RelayMessage.approve(id: id, allow: allow).message, replyHandler: nil)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        guard activationState == .activated else { return }
        store(session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        store(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let m = RelayMessage(message) else { return }
        inbox.withLock { _ = $0?.yield(m) }
    }

    private nonisolated func store(_ context: [String: Any]) {
        guard let settings = HubSettings(context: context), settings != .current else { return }
        settings.save()
        Task { @MainActor [weak self] in self?.onSettings?() }
    }
}
