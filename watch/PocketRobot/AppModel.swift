import Foundation
import Observation
import WatchKit

/// Agent turn state machine; drives the Visor expression and the caption.
@MainActor
@Observable
final class AppModel {
    enum AgentState: Equatable {
        case idle
        case listening
        case thinking
        case working(String?)
        case speaking(String)
        case done
        case error(String)
        case offline(String)

        var expression: VisorExpression {
            switch self {
            case .idle: .neutral
            case .listening: .surprised
            case .thinking: .thinking
            case .working: .working
            case .speaking: .speaking
            case .done: .success
            case .error: .angry
            case .offline: .sleepy
            }
        }
    }

    private(set) var state: AgentState = .idle {
        didSet {
            if state != oldValue { visor.set(state.expression) }
            if !isBusy { keepAlive.end() } // turn over (done, error, offline, cancelled)
        }
    }
    private(set) var heard = ""
    private(set) var reply = ""
    /// Debug: fixed caption when an expression was forced at launch.
    var debugCaption: String?

    @ObservationIgnored let visor = VisorModel()
    @ObservationIgnored private let recorder = Recorder()
    @ObservationIgnored private let speaker = Speaker()
    @ObservationIgnored private let hub = HubClient()
    @ObservationIgnored private let keepAlive = KeepAlive()
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var holding = false
    @ObservationIgnored private var pendingDone = false

    init() {
        speaker.onFinished = { [weak self] in self?.speechFinished() }
    }

    var caption: String {
        if let debugCaption { return debugCaption }
        switch state {
        case .idle: return reply.isEmpty ? "Hold to talk" : reply
        case .listening: return "Listening…"
        case .thinking: return heard.isEmpty ? "Thinking…" : "“\(heard)”"
        case .working(let tool): return tool.map { "Working: \($0)" } ?? "Working…"
        case .speaking(let text): return text
        case .done: return reply.isEmpty ? "Done" : reply
        case .error(let msg): return msg
        case .offline(let msg): return msg
        }
    }

    var isBusy: Bool {
        switch state {
        case .listening, .thinking, .working, .speaking: true
        default: false
        }
    }

    // MARK: - hub health

    func startHealthChecks() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkHealth()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func checkHealth() async {
        guard !isBusy else { return }
        let result = await hub.health()
        guard !isBusy else { return }
        switch (result, state) {
        case (.ok, .offline): state = .idle
        case (.ok, _): break
        case (.unauthorized, _): state = .offline("Token rejected")
        case (.unreachable, .idle), (.unreachable, .offline): state = .offline("Mac offline")
        case (.unreachable, _): break
        }
    }

    // MARK: - talking

    /// Long press began.
    func beginTalk() async {
        holding = true
        guard turnTask == nil else { return }
        guard await recorder.requestPermission() else {
            fail("Microphone not allowed")
            return
        }
        guard holding else { return } // released while the permission prompt was up
        do {
            speaker.stop()
            try recorder.start()
            resetTask?.cancel()
            heard = ""
            state = .listening
            WKInterfaceDevice.current().play(.start)
        } catch {
            fail("Mic unavailable")
        }
    }

    /// Finger lifted (send) or dragged away (cancel).
    func endTalk(cancel: Bool) {
        holding = false
        guard recorder.isRecording else { return }
        if cancel {
            recorder.cancel()
            state = .idle
            WKInterfaceDevice.current().play(.click)
            return
        }
        guard let file = recorder.stop() else {
            state = .idle
            return
        }
        send(file)
    }

    private func send(_ file: URL) {
        state = .thinking
        pendingDone = false
        keepAlive.begin()
        turnTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await hub.talk(audio: file) { event in self.handle(event) }
                if self.isBusy && !self.speaker.isSpeaking { self.finish() } // stream ended without "done"
            } catch HubError.unauthorized {
                self.speaker.stop()
                self.state = .offline("Token rejected")
                WKInterfaceDevice.current().play(.failure)
            } catch HubError.busy {
                self.fail("Busy with the last one")
            } catch is CancellationError {
            } catch HubError.unreachable {
                self.speaker.stop()
                self.state = .offline("Can't reach your Mac")
                WKInterfaceDevice.current().play(.failure)
            } catch {
                self.fail("Something went wrong")
            }
            self.turnTask = nil
        }
    }

    private func handle(_ event: HubEvent) {
        if let text = event.heard { heard = text }
        switch event.state {
        case "thinking": state = .thinking
        case "working": state = .working(event.tool)
        case "speaking":
            if let text = event.text, !text.isEmpty {
                reply = text
                state = .speaking(text)
                speaker.speak(text)
            }
        case "done":
            if speaker.isSpeaking { pendingDone = true } else { finish() }
        case "error":
            fail(event.message ?? "Something went wrong")
        default: break
        }
    }

    private func speechFinished() {
        if pendingDone { finish() }
    }

    private func finish() {
        pendingDone = false
        state = .done
        WKInterfaceDevice.current().play(.success)
        backToIdle(after: 3)
    }

    private func fail(_ message: String) {
        speaker.stop()
        pendingDone = false
        state = .error(message)
        WKInterfaceDevice.current().play(.failure)
        backToIdle(after: 4)
    }

    private func backToIdle(after seconds: Double) {
        resetTask?.cancel()
        let from = state
        resetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, self.state == from else { return }
            self.state = .idle
        }
    }
}
