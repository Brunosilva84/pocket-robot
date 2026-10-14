import Foundation
import Observation

/// Agent turn state machine; drives the Visor expression and the caption. Shared by the iPhone and the watch.
@MainActor
@Observable
final class AppModel {
    enum AgentState: Equatable {
        case idle
        case listening
        case thinking
        case working(String?)
        case approval(Approval)
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
            case .approval: .question
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
            #if os(watchOS)
            if !isBusy { keepAlive.end() } // turn over (done, error, offline, cancelled)
            #endif
        }
    }
    private(set) var heard = ""
    private(set) var reply = ""
    /// Debug: fixed caption when an expression was forced at launch.
    var debugCaption: String?

    @ObservationIgnored let visor = VisorModel()
    @ObservationIgnored private let recorder = Recorder()
    @ObservationIgnored private let speaker = Speaker()
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var turnTask: Task<Void, Never>?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var holding = false
    @ObservationIgnored private var pendingDone = false
    /// The approval on screen belongs to a turn this device is only relaying (iPhone, for the watch).
    @ObservationIgnored private var approvalIsRelayed = false
    #if os(watchOS)
    @ObservationIgnored private let keepAlive = KeepAlive()
    @ObservationIgnored let phone = PhoneLink()
    /// Last health check reached the hub directly.
    @ObservationIgnored private var hubReachable = true
    /// The current turn goes through the iPhone.
    @ObservationIgnored private var viaPhone = false
    @ObservationIgnored private var eventsThisTurn = 0
    #endif

    init() {
        speaker.onFinished = { [weak self] in self?.speechFinished() }
        #if os(watchOS)
        phone.onSettings = { [weak self] in self?.settingsChanged() }
        phone.activate()
        #endif
    }

    /// Settings are read on every request, so new ones apply to the next call.
    private var hub: HubClient { HubClient() }

    var caption: String {
        if let debugCaption { return debugCaption }
        switch state {
        case .idle: return reply.isEmpty ? Self.idleHint : reply
        case .listening: return "Listening…"
        case .thinking: return heard.isEmpty ? "Thinking…" : "“\(heard)”"
        case .working(let tool): return tool.map { "Working: \($0)" } ?? "Working…"
        case .approval(let a): return a.summary.isEmpty ? "Allow \(a.tool)?" : "\(a.tool): \(a.summary)"
        case .speaking(let text): return text
        case .done: return reply.isEmpty ? "Done" : reply
        case .error(let msg): return msg
        case .offline(let msg): return msg
        }
    }

    #if os(watchOS)
    private static let idleHint = "Hold to talk"
    #else
    private static let idleHint = "Hold the mic to talk, or type"
    #endif

    var isBusy: Bool {
        switch state {
        case .listening, .thinking, .working, .approval, .speaking: true
        default: false
        }
    }

    var approval: Approval? {
        if case .approval(let a) = state { a } else { nil }
    }

    var isOffline: Bool {
        if case .offline = state { true } else { false }
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

    /// New hub URL or token: check right away and start the next conversation from a clean caption.
    func settingsChanged() {
        guard healthTask != nil else { return }
        if !isBusy { reply = "" }
        startHealthChecks()
    }

    private func checkHealth() async {
        guard !isBusy else { return }
        var result = await hub.health()
        guard !isBusy else { return }
        #if os(watchOS)
        hubReachable = result != .unreachable
        if result == .unreachable && phone.isReachable { result = .ok } // turns go through the iPhone
        #endif
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
        guard turnTask == nil, approval == nil else { return }
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
            Haptic.start.play()
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
            Haptic.click.play()
            return
        }
        guard let file = recorder.stop(), let data = try? Data(contentsOf: file) else {
            state = .idle
            return
        }
        send(.audio(data))
    }

    /// Typed prompt (iPhone). Returns false when a turn is already running.
    @discardableResult
    func send(text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, turnTask == nil, approval == nil, !recorder.isRecording else { return false }
        speaker.stop()
        resetTask?.cancel()
        heard = text
        send(.text(text))
        return true
    }

    private func send(_ body: TalkBody) {
        state = .thinking
        pendingDone = false
        #if os(watchOS)
        keepAlive.begin()
        #endif
        turnTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await route(body)
                if self.isBusy && !self.speaker.isSpeaking { self.finish() } // stream ended without "done"
            } catch HubError.unauthorized {
                self.speaker.stop()
                self.state = .offline("Token rejected")
                Haptic.failure.play()
            } catch HubError.busy {
                self.fail("Busy with the last one")
            } catch is CancellationError {
            } catch HubError.unreachable {
                self.speaker.stop()
                self.state = .offline("Can't reach your Mac")
                Haptic.failure.play()
            } catch {
                self.fail("Something went wrong")
            }
            self.turnTask = nil
        }
    }

    /// Straight to the hub; on the watch, through the iPhone when the hub is out of reach.
    private func route(_ body: TalkBody) async throws {
        #if os(watchOS)
        viaPhone = false
        eventsThisTurn = 0
        if case .audio(let data) = body, phone.isReachable {
            if !hubReachable {
                viaPhone = true
                return try await phone.talk(data) { event in self.handle(event) }
            }
            do {
                try await hub.talk(body) { event in self.handle(event) }
            } catch HubError.unreachable where eventsThisTurn == 0 && phone.isReachable {
                viaPhone = true
                try await phone.talk(data) { event in self.handle(event) }
            }
            return
        }
        #endif
        try await hub.talk(body) { event in self.handle(event) }
    }

    private func handle(_ event: HubEvent) {
        #if os(watchOS)
        eventsThisTurn += 1
        #endif
        if let text = event.heard { heard = text }
        if let id = event.approval {
            decided(id, allowed: event.allowed ?? false)
            return
        }
        switch event.state {
        case "thinking": state = .thinking
        case "working": state = .working(event.tool)
        case "approval":
            if let a = Approval(event) {
                approvalIsRelayed = false
                state = .approval(a)
                Haptic.attention.play()
            }
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

    // MARK: - approvals

    /// Approve / Deny the request on screen.
    func approve(_ allow: Bool) {
        guard let a = approval else { return }
        Haptic.click.play()
        leaveApproval(a, allowed: allow)
        #if os(watchOS)
        if viaPhone {
            phone.approve(id: a.id, allow: allow)
            return
        }
        #endif
        let hub = hub
        Task {
            // 404: already decided elsewhere or timed out; unreachable: the hub denies after 60 s
            try? await hub.approve(id: a.id, allow: allow)
        }
    }

    /// The hub's decision (from this device, another one, or the 60 s timeout).
    private func decided(_ id: String, allowed: Bool) {
        guard let a = approval, a.id == id else { return }
        leaveApproval(a, allowed: allowed)
    }

    private func leaveApproval(_ a: Approval, allowed: Bool) {
        if approvalIsRelayed {
            approvalIsRelayed = false
            state = .idle
        } else {
            state = allowed ? .working(a.tool) : .thinking
        }
    }

    /// iPhone: events of a turn relayed for the watch, so its approvals can be answered here too.
    func relayed(_ event: HubEvent) {
        guard turnTask == nil else { return }
        if event.state == "approval", let a = Approval(event) {
            approvalIsRelayed = true
            state = .approval(a)
            Haptic.attention.play()
        } else if let id = event.approval {
            decided(id, allowed: event.allowed ?? false)
        }
    }

    /// iPhone: the relayed turn ended; drop its approval if still on screen.
    func relayEnded() {
        guard approvalIsRelayed else { return }
        approvalIsRelayed = false
        state = .idle
    }

    /// Clears the caption after the hub forgot the conversation.
    func forgetConversation() {
        guard !isBusy else { return }
        heard = ""
        reply = ""
        if case .done = state { state = .idle }
    }

    // MARK: - end of turn

    private func speechFinished() {
        if pendingDone { finish() }
    }

    private func finish() {
        pendingDone = false
        state = .done
        Haptic.success.play()
        backToIdle(after: 3)
    }

    private func fail(_ message: String) {
        speaker.stop()
        pendingDone = false
        state = .error(message)
        Haptic.failure.play()
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

    #if DEBUG
    /// Screenshots: show a state without a hub.
    func debugShow(_ state: AgentState, heard: String = "", reply: String = "") {
        self.heard = heard
        self.reply = reply
        self.state = state
    }
    #endif
}
