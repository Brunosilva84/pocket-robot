import WatchKit

/// Keeps the app running (and frontmost) while a turn is in flight, so the reply still arrives
/// after the wrist goes down. Uses a self-care extended runtime session (up to 10 minutes).
/// Best effort: if the session can't start, the app just works without it.
@MainActor
final class KeepAlive: NSObject, WKExtendedRuntimeSessionDelegate {
    private var session: WKExtendedRuntimeSession?
    private var wanted = false

    func begin() {
        wanted = true
        if let session, session.state == .running || session.state == .notStarted { return }
        let s = WKExtendedRuntimeSession()
        s.delegate = self
        session = s
        s.start()
    }

    func end() {
        wanted = false
        guard let s = session, s.state == .running else { return } // a pending start is ended in didStart
        session = nil
        s.invalidate()
    }

    private func started(_ id: ObjectIdentifier) {
        guard let s = session, ObjectIdentifier(s) == id, !wanted else { return }
        session = nil
        s.invalidate()
    }

    private func invalidated(_ id: ObjectIdentifier) {
        if let s = session, ObjectIdentifier(s) == id { session = nil }
    }

    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        let id = ObjectIdentifier(extendedRuntimeSession)
        Task { @MainActor [weak self] in self?.started(id) }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: (any Error)?) {
        let id = ObjectIdentifier(extendedRuntimeSession)
        Task { @MainActor [weak self] in self?.invalidated(id) }
    }
}
