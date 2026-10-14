import SwiftUI
import WidgetKit

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RobotEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularView()
        case .accessoryRectangular:
            RectangularView()
        case .accessoryCorner:
            CornerView()
        default:
            InlineView()
        }
    }
}

private struct CircularView: View {
    var body: some View {
        RobotFace()
            .padding(4)
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
    }
}

private struct RectangularView: View {
    var body: some View {
        HStack(spacing: 8) {
            RobotFace()
            VStack(alignment: .leading, spacing: 2) {
                Text("Pocket Robot")
                    .font(.headline)
                    .widgetAccentable()
                Text("Hold to talk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

private struct CornerView: View {
    var body: some View {
        RobotFace()
            .widgetLabel("Pocket Robot")
            .containerBackground(for: .widget) {
                Color.clear
            }
    }
}

private struct InlineView: View {
    var body: some View {
        Label("Pocket Robot", systemImage: "waveform")
            .containerBackground(for: .widget) {
                Color.clear
            }
    }
}

#Preview("Circular", as: .accessoryCircular) {
    PocketRobotComplication()
} timeline: {
    RobotEntry(date: .now)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    PocketRobotComplication()
} timeline: {
    RobotEntry(date: .now)
}

#Preview("Corner", as: .accessoryCorner) {
    PocketRobotComplication()
} timeline: {
    RobotEntry(date: .now)
}

#Preview("Inline", as: .accessoryInline) {
    PocketRobotComplication()
} timeline: {
    RobotEntry(date: .now)
}
