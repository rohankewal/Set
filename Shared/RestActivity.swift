#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

/// The contract between the app and its Live Activity. Shared by both targets,
/// so there's exactly one definition of what a rest period looks like.
///
/// The countdown is expressed as an end date rather than a remaining number:
/// the system renders the timer itself, which means the Dynamic Island stays
/// accurate to the second without the app waking up to push an update.
#if canImport(ActivityKit)
// `nonisolated`: the module defaults to MainActor isolation, but ActivityKit
// hands these values to the widget extension off the main actor.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// When the rest period ends. Nil while paused.
        var endsAt: Date?
        /// Seconds left, used while paused and for the compact presentations.
        var remaining: TimeInterval
        /// Total length, for the progress ring.
        var total: TimeInterval
        var isPaused: Bool
        /// Sets completed so far this session.
        var setsLogged: Int
        /// What to do next, e.g. "Back Squat · 120kg × 5".
        var nextUp: String
    }

    /// Fixed for the life of the activity.
    var sessionTitle: String
}
#endif
