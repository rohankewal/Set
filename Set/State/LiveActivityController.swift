#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation

/// Mirrors the rest clock to the Lock Screen and Dynamic Island.
///
/// The countdown is handed to the system as an end date, so the island ticks
/// accurately while the app is suspended — no background execution, no push
/// notifications, nothing leaving the device. Every call is a no-op when Live
/// Activities are unavailable or switched off, so the engine can call them
/// unconditionally.
@MainActor
final class LiveActivityController {
    #if canImport(ActivityKit)
    private var activity: Activity<RestActivityAttributes>?
    #endif

    private var isEnabled: Bool {
        #if canImport(ActivityKit)
        ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        false
        #endif
    }

    func start(
        sessionTitle: String,
        endsAt: Date,
        total: TimeInterval,
        setsLogged: Int,
        nextUp: String
    ) {
        #if canImport(ActivityKit)
        guard isEnabled else { return }

        let state = RestActivityAttributes.ContentState(
            endsAt: endsAt,
            remaining: max(0, endsAt.timeIntervalSinceNow),
            total: total,
            isPaused: false,
            setsLogged: setsLogged,
            nextUp: nextUp
        )

        // An activity already on screen is updated rather than replaced, so the
        // island doesn't flicker between sets.
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: endsAt)) }
            return
        }

        // A failure here means the user has Live Activities switched off, or the
        // system is at its limit — neither is worth interrupting a workout for.
        activity = try? Activity.request(
            attributes: RestActivityAttributes(sessionTitle: sessionTitle),
            content: ActivityContent(state: state, staleDate: endsAt),
            pushType: nil
        )
        #endif
    }

    func update(
        endsAt: Date?,
        remaining: TimeInterval,
        total: TimeInterval,
        isPaused: Bool,
        setsLogged: Int,
        nextUp: String
    ) {
        #if canImport(ActivityKit)
        guard let activity else { return }
        let state = RestActivityAttributes.ContentState(
            endsAt: endsAt,
            remaining: remaining,
            total: total,
            isPaused: isPaused,
            setsLogged: setsLogged,
            nextUp: nextUp
        )
        let stale = endsAt ?? Date.now.addingTimeInterval(max(remaining, 60))
        Task { await activity.update(ActivityContent(state: state, staleDate: stale)) }
        #endif
    }

    func end() {
        #if canImport(ActivityKit)
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        #endif
    }
}
