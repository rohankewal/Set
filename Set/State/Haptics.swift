import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Thin wrapper so haptics respect the user's preference in exactly one place.
@MainActor
enum Haptics {
    enum Note { case tick, complete, record, warning }

    static var enabled = true

    static func play(_ note: Note) {
        guard enabled else { return }
        #if canImport(UIKit) && !os(visionOS)
        switch note {
        case .tick:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        case .complete:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .record:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}
