import SwiftUI

@main
struct PocketRobotApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(app: app)
                .onAppear(perform: start)
        }
    }

    private func start() {
        #if DEBUG
        // `-approval YES` shows a pending approval and skips the hub (for screenshots)
        if UserDefaults.standard.bool(forKey: "approval") {
            app.visor.sleepAfter = .infinity
            app.debugShow(.approval(Approval(id: "demo", tool: "Bash", summary: "npm test")))
            return
        }
        // `-expr <name>` shows one expression and skips the hub (for screenshots)
        if let raw = UserDefaults.standard.string(forKey: "expr"), let e = VisorExpression(rawValue: raw) {
            app.debugCaption = UserDefaults.standard.string(forKey: "caption") ?? raw
            app.visor.sleepAfter = .infinity
            switch e {
            case .dizzy: app.visor.dizzy(); app.visor.play(.dizzy, seconds: .infinity)
            case .annoyed, .yawn: app.visor.play(e, seconds: .infinity)
            default: app.visor.set(e)
            }
            return
        }
        #endif
        app.startHealthChecks()
    }
}
