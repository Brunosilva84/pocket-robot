#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

/// Turn feedback, mapped to each device's haptics.
enum Haptic {
    case start, click, success, failure, attention

    @MainActor
    func play() {
        #if os(watchOS)
        let type: WKHapticType = switch self {
        case .start: .start
        case .click: .click
        case .success: .success
        case .failure: .failure
        case .attention: .notification
        }
        WKInterfaceDevice.current().play(type)
        #else
        switch self {
        case .start: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .click: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure: UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .attention: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}
