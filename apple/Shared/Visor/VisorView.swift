import SwiftUI

/// Live robot: one timeline clock drives both the simulation step and the drawing.
/// Always On (`lowPower`): ~1 Hz updates and a dim, still robot; otherwise animation capped at 30 fps.
struct VisorView: View {
    enum Placement { case watch, watchCompact, centered }

    let model: VisorModel
    var lowPower = false
    var placement = Placement.watch

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
        Canvas { [lowPower, placement] g, size in
            let now = date.timeIntervalSinceReferenceDate
            model.lowPower = lowPower
            model.step(now: now)
            let layout: VisorLayout = switch placement {
            case .watch: .watch(size)
            case .watchCompact: .watchCompact(size)
            case .centered: .centered(size)
            }
            model.draw(&g, layout: layout, now: now)
        }
    }
}
