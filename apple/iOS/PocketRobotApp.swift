import SwiftUI

@main
struct PocketRobotApp: App {
    private let app: AppModel
    private let relay: WatchRelay

    init() {
        // Created here, not on appear: the watch can wake this app in the background to relay a turn.
        app = AppModel()
        relay = WatchRelay(app: app)
        relay.activate()
    }

    var body: some Scene {
        WindowGroup {
            MainView(app: app, relay: relay)
                .preferredColorScheme(.dark)
                .onAppear(perform: start)
        }
    }

    private func start() {
        #if DEBUG
        // Screenshots, no hub: `-expr <name>` (+ `-caption`), `-approval YES`, `-demo YES` (sample reply,
        // history and settings), `-screen history|settings`.
        let args = UserDefaults.standard
        if args.bool(forKey: "approval") {
            app.visor.sleepAfter = .infinity
            app.debugShow(.approval(Approval(id: "demo", tool: "Bash", summary: "npm test -- --watch=false")),
                          heard: "Run the tests")
            return
        }
        if let raw = args.string(forKey: "expr"), let e = VisorExpression(rawValue: raw) {
            app.debugCaption = args.string(forKey: "caption") ?? raw
            app.visor.sleepAfter = .infinity
            switch e {
            case .dizzy: app.visor.dizzy(); app.visor.play(.dizzy, seconds: .infinity)
            case .annoyed, .yawn: app.visor.play(e, seconds: .infinity)
            default: app.visor.set(e)
            }
            return
        }
        if args.bool(forKey: "demo") {
            app.visor.sleepAfter = .infinity
            app.debugShow(.idle, heard: "What's left on the todo list?",
                          reply: "Two things: the README section on Tailscale, and the watch complication.")
            return
        }
        #endif
        app.startHealthChecks()
    }
}
