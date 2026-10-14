import SwiftUI

struct ContentView: View {
    let app: AppModel

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    @State private var touchStart: Date?
    @State private var startPoint: CGPoint = .zero
    @State private var travelled: CGFloat = 0
    @State private var lastPoint: CGPoint = .zero
    @State private var petted = false
    @State private var moved = false
    @State private var recordingGesture = false
    @State private var cancelArmed = false
    @State private var holdTask: Task<Void, Never>?
    @State private var crown = 0.0
    @State private var crownStamp = Date()

    private let holdDelay = 0.35
    private let moveSlop: CGFloat = 8
    private let petDistance: CGFloat = 50
    private let cancelDistance: CGFloat = 55

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    VisorView(model: app.visor, lowPower: reduced,
                              placement: app.approval == nil ? .watch : .watchCompact)
                        .ignoresSafeArea()
                    if app.approval == nil {
                        Text(cancelArmed ? "Release to cancel" : app.caption)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(cancelArmed ? .orange : .white.opacity(reduced ? 0.4 : 0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 2)
                    }
                }
                .contentShape(Rectangle())
                .gesture(touch(in: geo.size))
            }
            if let approval = app.approval {
                approvalPanel(approval)
            }
        }
        .background(Color.black)
        .focusable()
        .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000, sensitivity: .high,
                              isContinuous: true, isHapticFeedbackEnabled: false)
        .onChange(of: crown) { old, new in
            let now = Date()
            let dt = max(0.01, now.timeIntervalSince(crownStamp))
            crownStamp = now
            app.visor.crownSpin(velocity: (new - old) / dt)
        }
    }

    /// Claude Code wants to run a gated tool: what it is, and Deny / Approve.
    private func approvalPanel(_ approval: Approval) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text(approval.tool)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
                if !approval.summary.isEmpty {
                    Text(approval.summary)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            HStack(spacing: 6) {
                Button(role: .destructive) { app.approve(false) } label: {
                    Text("Deny").frame(maxWidth: .infinity)
                }
                .tint(.red)
                Button { app.approve(true) } label: {
                    Text("Approve").frame(maxWidth: .infinity)
                }
                .tint(.green)
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(approval.tool) wants to run \(approval.summary)")
    }

    /// Always On (wrist down); `-aod YES` forces the look in DEBUG builds for screenshots.
    private var reduced: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "aod") { return true }
        #endif
        return isLuminanceReduced
    }

    /// One gesture for tap (poke), stroke (pet + look), and hold-to-talk.
    private func touch(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if touchStart == nil { began(at: v.location) }
                let p = v.location
                travelled += hypot(p.x - lastPoint.x, p.y - lastPoint.y)
                lastPoint = p
                let fromStart = hypot(p.x - startPoint.x, p.y - startPoint.y)
                if fromStart > moveSlop { moved = true }
                app.visor.aim(x: (p.x - size.width / 2) / (size.width / 2),
                              y: (p.y - size.height * 0.44) / (size.width / 2))
                if recordingGesture {
                    let outside = p.x < 0 || p.y < 0 || p.x > size.width || p.y > size.height
                    cancelArmed = fromStart > cancelDistance || outside
                } else if moved {
                    holdTask?.cancel()
                    if !petted && travelled > petDistance { petted = true; app.visor.pet() }
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                if recordingGesture {
                    app.endTalk(cancel: cancelArmed)
                } else if !moved, let start = touchStart, Date().timeIntervalSince(start) < holdDelay {
                    app.visor.poke()
                }
                app.visor.endAim()
                touchStart = nil
                recordingGesture = false
                cancelArmed = false
            }
    }

    private func began(at p: CGPoint) {
        touchStart = Date()
        startPoint = p; lastPoint = p
        travelled = 0; petted = false; moved = false
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(holdDelay))
            guard !Task.isCancelled, touchStart != nil, !moved else { return }
            recordingGesture = true
            await app.beginTalk()
        }
    }
}
