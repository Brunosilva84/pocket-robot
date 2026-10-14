import SwiftUI

/// The robot on top, what it's doing under it, and a composer: type, or hold the mic to talk.
struct MainView: View {
    enum Screen: String, Hashable {
        case history, settings
    }

    let app: AppModel
    let relay: WatchRelay

    @State private var path: [Screen] = []
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                RobotStage(app: app)
                caption
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                Composer(app: app, draft: $draft, typing: $typing)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: Screen.history) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                }
                ToolbarItem(placement: .principal) {
                    StatusPill(offline: app.isOffline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Screen.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .history: HistoryView()
                case .settings: SettingsView(app: app, relay: relay)
                }
            }
        }
        .tint(Color(red: 0.22, green: 0.74, blue: 0.97))
        .sheet(item: Binding(get: { app.approval }, set: { _ in })) { approval in
            ApprovalSheet(approval: approval) { app.approve($0) }
        }
        .onAppear {
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: "screen"), let screen = Screen(rawValue: raw) {
                path = [screen]
            }
            #endif
        }
    }

    private var caption: some View {
        VStack(spacing: 8) {
            if showsHeard {
                Text("“\(app.heard)”")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
            Text(app.caption)
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(5)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: app.caption)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
    }

    /// The prompt above the reply once the robot answers (while thinking it is the caption itself).
    private var showsHeard: Bool {
        guard !app.heard.isEmpty, app.debugCaption == nil else { return false }
        switch app.state {
        case .working, .approval, .speaking, .done: return true
        case .idle: return !app.reply.isEmpty
        default: return false
        }
    }
}

/// The robot: tap to poke, stroke to pet, and it looks at your finger.
private struct RobotStage: View {
    let app: AppModel

    @State private var touchStart: Date?
    @State private var startPoint: CGPoint = .zero
    @State private var lastPoint: CGPoint = .zero
    @State private var travelled: CGFloat = 0
    @State private var petted = false
    @State private var moved = false

    var body: some View {
        GeometryReader { geo in
            VisorView(model: app.visor, placement: .centered)
                .contentShape(Rectangle())
                .gesture(touch(in: geo.size))
        }
        .accessibilityElement()
        .accessibilityLabel("Robot")
        .accessibilityValue(app.caption)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { app.visor.poke() }
    }

    private func touch(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                let p = v.location
                if touchStart == nil {
                    touchStart = .now
                    startPoint = p; lastPoint = p
                    travelled = 0; petted = false; moved = false
                }
                travelled += hypot(p.x - lastPoint.x, p.y - lastPoint.y)
                lastPoint = p
                if hypot(p.x - startPoint.x, p.y - startPoint.y) > 10 { moved = true }
                let half = min(size.width, size.height) / 2
                app.visor.aim(x: (p.x - size.width / 2) / half, y: (p.y - size.height / 2) / half)
                if moved && !petted && travelled > 80 { petted = true; app.visor.pet() }
            }
            .onEnded { _ in
                if !moved, let start = touchStart, Date.now.timeIntervalSince(start) < 0.35 { app.visor.poke() }
                app.visor.endAim()
                touchStart = nil
            }
    }
}

/// Text field plus a mic that records while held (slide up to cancel); the mic becomes Send when there's text.
private struct Composer: View {
    let app: AppModel
    @Binding var draft: String
    var typing: FocusState<Bool>.Binding

    @State private var holding = false
    @State private var cancelArmed = false

    private let cancelDistance: CGFloat = 70

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $draft, prompt: Text(holding ? hint : "Type a message").foregroundStyle(.white.opacity(0.4)))
                .focused(typing)
                .submitLabel(.send)
                .onSubmit(sendText)
                .disabled(holding)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Capsule().fill(.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1)))
            if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                micButton
            } else {
                Button(action: sendText) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .bold))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.accentColor))
                        .foregroundStyle(.black)
                }
                .disabled(app.isBusy)
                .accessibilityLabel("Send")
            }
        }
    }

    private var hint: String { cancelArmed ? "Release to cancel" : "Slide up to cancel" }

    private var micButton: some View {
        Image(systemName: cancelArmed ? "xmark" : "mic.fill")
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(holding ? .black : .white)
            .frame(width: 52, height: 52)
            .background(Circle().fill(holding ? (cancelArmed ? Color.orange : Color.accentColor) : .white.opacity(0.12)))
            .scaleEffect(holding ? 1.25 : 1)
            .animation(.spring(duration: 0.25), value: holding)
            .animation(.spring(duration: 0.25), value: cancelArmed)
            .opacity(app.isBusy && !holding ? 0.4 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !holding {
                            holding = true
                            typing.wrappedValue = false
                            Task { await app.beginTalk() }
                        }
                        cancelArmed = v.translation.height < -cancelDistance
                    }
                    .onEnded { _ in
                        app.endTalk(cancel: cancelArmed)
                        holding = false
                        cancelArmed = false
                    }
            )
            .accessibilityLabel("Hold to talk")
            .accessibilityAddTraits(.isButton)
    }

    private func sendText() {
        if app.send(text: draft) {
            draft = ""
            typing.wrappedValue = false
        }
    }
}

/// Hub reachability in the title bar.
private struct StatusPill: View {
    let offline: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(offline ? Color(red: 0.65, green: 0.55, blue: 0.98) : Color(red: 0.29, green: 0.87, blue: 0.5))
                .frame(width: 7, height: 7)
            Text(offline ? "Offline" : "Pocket Robot")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
