import SwiftUI
import WidgetKit

@main
struct PocketRobotWidgetBundle: WidgetBundle {
    var body: some Widget {
        PocketRobotComplication()
    }
}

/// The robot's face on the watch face. Tapping any family opens the app (WidgetKit's default).
struct PocketRobotComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PocketRobotComplication", provider: RobotProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("Pocket Robot")
        .description("Your robot on the watch face. Tap to talk.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
