import WidgetKit

struct RobotEntry: TimelineEntry {
    let date: Date
}

/// The complication never changes: one entry, never refreshed.
struct RobotProvider: TimelineProvider {
    func placeholder(in context: Context) -> RobotEntry {
        RobotEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RobotEntry) -> Void) {
        completion(RobotEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RobotEntry>) -> Void) {
        completion(Timeline(entries: [RobotEntry(date: .now)], policy: .never))
    }
}
