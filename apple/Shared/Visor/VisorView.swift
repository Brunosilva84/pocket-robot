import SwiftUI

/// Live robot: one timeline clock drives both the simulation step and the drawing.
/// Always On (`lowPower`): ~1 Hz updates and a dim, still robot; otherwise animation capped at 30 fps.
struct VisorView: View {
    let model: VisorModel
    var lowPower = false

    var body: some View {
        Group {
            if lowPower {
                TimelineView(.periodic(from: .now, by: 1)) { canvas($0.date) }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { canvas($0.date) }
            }
        }
        .background(Color.black)
    }

    private func canvas(_ date: Date) -> some View {
        Canvas { [lowPower] g, size in
            let now = date.timeIntervalSinceReferenceDate
            model.lowPower = lowPower
            model.step(now: now)
            model.draw(&g, layout: .watch(size), now: now)
        }
    }
}
