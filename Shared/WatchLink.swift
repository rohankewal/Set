import Foundation

/// The wire format between phone and watch.
///
/// The phone owns the data — there is one SwiftData store and it lives there.
/// The watch is a remote control: it receives a snapshot of what's happening and
/// sends back intents ("log the set", "skip the rest"). Nothing is persisted on
/// the watch, so the two can never disagree about what was logged.
nonisolated enum WatchLink {
    /// Keys used in the `WCSession` dictionaries. Kept tiny — these payloads are
    /// sent on every set.
    nonisolated enum Key {
        static let snapshot = "s"
        static let command = "c"
    }

    /// What the watch shows.
    nonisolated struct Snapshot: Codable, Equatable, Sendable {
        var isRunning = false
        var sessionTitle = ""
        var exercise = ""
        /// Formatted for display, because unit conversion is the phone's job.
        var weight = ""
        var unit = ""
        var reps = 0
        var usesWeight = true
        var setNumber = 1
        var setsLogged = 0
        var startedAt: Date?
        /// End of the current rest, or nil when not resting.
        var restEndsAt: Date?
        var restRemaining: TimeInterval = 0
        var isRestPaused = false

        var isResting: Bool {
            if isRestPaused { return true }
            guard let restEndsAt else { return false }
            return restEndsAt > .now
        }
    }

    /// What the watch can ask for.
    nonisolated enum Command: String, Codable, Sendable {
        case logSet
        case skipRest
        case toggleRest
        case addFifteen
        case nextExercise
        case previousExercise
        case requestSnapshot
    }

    static func encode(_ snapshot: Snapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot) else { return [:] }
        return [Key.snapshot: data]
    }

    static func decodeSnapshot(_ payload: [String: Any]) -> Snapshot? {
        guard let data = payload[Key.snapshot] as? Data else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func encode(_ command: Command) -> [String: Any] {
        [Key.command: command.rawValue]
    }

    static func decodeCommand(_ payload: [String: Any]) -> Command? {
        guard let raw = payload[Key.command] as? String else { return nil }
        return Command(rawValue: raw)
    }
}
