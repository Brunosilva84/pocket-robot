import SwiftUI

/// Past turns from the hub, newest first: what you said, what the robot answered.
struct HistoryView: View {
    @State private var turns: [HistoryTurn] = []
    @State private var loading = true
    @State private var failure: String?

    var body: some View {
        List {
            ForEach(Array(turns.reversed().enumerated()), id: \.offset) { _, turn in
                TurnRow(turn: turn)
            }
        }
        .listStyle(.plain)
        .overlay {
            if turns.isEmpty {
                if loading {
                    ProgressView()
                } else {
                    ContentUnavailableView(failure == nil ? "No turns yet" : "Couldn't load history",
                                           systemImage: failure == nil ? "bubble.left.and.bubble.right" : "wifi.slash",
                                           description: Text(failure ?? "What you say and the robot's replies show up here."))
                }
            }
        }
        .navigationTitle("History")
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        defer { loading = false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demo") {
            turns = HistoryTurn.demo
            return
        }
        #endif
        do {
            turns = try await HubClient().history()
            failure = nil
        } catch HubError.unauthorized {
            failure = "The hub rejected the token. Check it in Settings."
        } catch {
            failure = "Can't reach the hub on your Mac."
        }
    }
}

private struct TurnRow: View {
    let turn: HistoryTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let date = turn.date {
                    Text(date, format: .relative(presentation: .named))
                }
                Spacer()
                if turn.ok == false {
                    Label("Failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let heard = turn.heard, !heard.isEmpty {
                Text("“\(heard)”")
                    .foregroundStyle(.white.opacity(0.6))
            }
            if let reply = turn.reply, !reply.isEmpty {
                Text(reply)
                    .font(.system(.body, design: .rounded))
            }
        }
        .padding(.vertical, 6)
    }
}

#if DEBUG
extension HistoryTurn {
    /// Sample turns for screenshots (`-demo YES`).
    static var demo: [HistoryTurn] {
        let now = Date.now
        func at(_ minutes: Double) -> String { now.addingTimeInterval(-minutes * 60).formatted(.iso8601) }
        return [
            HistoryTurn(at: at(95), heard: "Make a folder for the trip notes", reply: "Done, it's called trip-notes.", ok: true),
            HistoryTurn(at: at(52), heard: "What changed in the hub today?", reply: "Approvals, typed messages and the history endpoint.", ok: true),
            HistoryTurn(at: at(20), heard: "Deploy the site", reply: "Something went wrong.", ok: false),
            HistoryTurn(at: at(3), heard: "What's left on the todo list?", reply: "Two things: the README section on Tailscale, and the watch complication.", ok: true),
        ]
    }
}
#endif
