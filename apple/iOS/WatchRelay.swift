import Foundation
import Observation
import UIKit
import WatchConnectivity

/// iPhone side of WatchConnectivity: pushes hub settings to the watch, and runs turns for the watch
/// when it can't reach the hub itself (events stream back one message each).
@MainActor
@Observable
final class WatchRelay: NSObject, WCSessionDelegate {
    enum WatchStatus: Equatable {
        case unsupported, notPaired, notInstalled, notReachable, reachable

        var label: String {
            switch self {
            case .unsupported: "Not supported"
            case .notPaired: "No watch paired"
            case .notInstalled: "App not on the watch"
            case .notReachable: "Not reachable"
            case .reachable: "Connected"
            }
        }
    }

    private(set) var status = WatchStatus.notPaired
    @ObservationIgnored private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    func activate() {
        guard WCSession.isSupported() else {
            status = .unsupported
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the hub URL and token to the watch (it keeps the latest).
    func push(_ settings: HubSettings = .current) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(settings.context)
    }

    private func refresh() {
        let session = WCSession.default
        status = !session.isPaired ? .notPaired
            : !session.isWatchAppInstalled ? .notInstalled
            : session.isReachable ? .reachable : .notReachable
    }

    // MARK: - relay

    private func receive(_ message: RelayMessage) {
        switch message {
        case .talk(let audio): relayTalk(audio)
        case .approve(let id, let allow):
            Task { try? await HubClient().approve(id: id, allow: allow) }
        case .event, .end, .error: break
        }
    }

    private func relayTalk(_ audio: Data) {
        // woken in the background by the watch: ask for time to finish the turn
        let background = UIApplication.shared.beginBackgroundTask(withName: "relay")
        Task {
            do {
                try await HubClient().talk(.audio(audio)) { event in
                    self.send(.event(event))
                    self.app.relayed(event)
                }
                send(.end)
            } catch {
                send(.error(RelayMessage.errorName(error)))
            }
            app.relayEnded()
            UIApplication.shared.endBackgroundTask(background)
        }
    }

    private func send(_ message: RelayMessage) {
        WCSession.default.sendMessage(message.message, replyHandler: nil)
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor in
            self.refresh()
            self.push()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // switched to another watch: activate again for the new one
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refresh()
            self.push()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let m = RelayMessage(message) else { return }
        Task { @MainActor in self.receive(m) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // long recordings come as a file; it is deleted when this returns, so read it now
        guard file.metadata?["talk"] as? Bool == true, let audio = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in self.relayTalk(audio) }
    }
}
