import SwiftUI

/// Live robot: one timeline clock drives both the simulation step and the drawing.
struct VisorView: View {
    let model: VisorModel

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { g, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                model.step(now: now)
                model.draw(&g, layout: .watch(size), now: now)
            }
        }
        .background(Color.black)
    }
}
