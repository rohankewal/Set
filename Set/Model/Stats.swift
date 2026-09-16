import Foundation
import SwiftData

// MARK: - Per-exercise bests

struct ExerciseBests: Equatable, Sendable {
    var heaviestKg: Double = 0
    var estimatedMaxKg: Double = 0
    var bestReps: Int = 0
    var bestSessionVolumeKg: Double = 0
    var lastSet: SetSnapshot?

    var isEmpty: Bool {
        heaviestKg == 0 && bestReps == 0 && bestSessionVolumeKg == 0
    }
}

/// A value-type copy of a set, so summaries can be passed around without
/// dragging managed objects (and their context) along.
struct SetSnapshot: Equatable, Sendable {
    var weightKg: Double
    var reps: Int
    var seconds: Int
    var date: Date
}

enum Stats {
    /// Bests across every completed session, optionally ignoring one session
    /// (used to ask "was this a PR *before* today?").
    static func bests(
        for exerciseName: String,
        in sessions: [WorkoutSession],
        excluding sessionID: UUID? = nil
    ) -> ExerciseBests {
        var result = ExerciseBests()
        var latest: (Date, SetSnapshot)?

        for session in sessions where session.endedAt != nil && session.id != sessionID {
            var sessionVolume: Double = 0
            for block in session.allBlocks where block.name == exerciseName {
                for set in block.allSets where set.isComplete && set.kind.countsTowardVolume {
                    if set.kind.countsTowardLoadRecords {
                        result.heaviestKg = max(result.heaviestKg, set.weightKg)
                    }
                    if set.kind.countsTowardLoadRecords {
                        result.estimatedMaxKg = max(result.estimatedMaxKg, set.estimatedOneRepMaxKg)
                    }
                    result.bestReps = max(result.bestReps, set.reps)
                    sessionVolume += set.volumeKg
                    let stamp = set.completedAt ?? session.startedAt
                    let snapshot = SetSnapshot(
                        weightKg: set.weightKg,
                        reps: set.reps,
                        seconds: set.seconds,
                        date: stamp
                    )
                    if latest == nil || stamp > latest!.0 { latest = (stamp, snapshot) }
                }
            }
            result.bestSessionVolumeKg = max(result.bestSessionVolumeKg, sessionVolume)
        }

        result.lastSet = latest?.1
        return result
    }

    /// Total tonnage per ISO week, oldest first, padded so the chart never jumps.
    static func weeklyVolume(
        for sessions: [WorkoutSession],
        weeks: Int = 8,
        calendar: Calendar = .current
    ) -> [(weekStart: Date, volumeKg: Double, sessions: Int)] {
        let now = Date.now
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }

        var buckets: [Date: (Double, Int)] = [:]
        for offset in 0..<weeks {
            if let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek) {
                buckets[start] = (0, 0)
            }
        }

        for session in sessions where session.endedAt != nil {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: session.startedAt)?.start,
                  buckets[start] != nil else { continue }
            let existing = buckets[start] ?? (0, 0)
            buckets[start] = (existing.0 + session.volumeKg, existing.1 + 1)
        }

        return buckets
            .sorted { $0.key < $1.key }
            .map { (weekStart: $0.key, volumeKg: $0.value.0, sessions: $0.value.1) }
    }

    /// Consecutive weeks (counting back from this one) containing at least one session.
    static func weekStreak(for sessions: [WorkoutSession], calendar: Calendar = .current) -> Int {
        let weeks = Set(
            sessions
                .filter { $0.endedAt != nil }
                .compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start }
        )
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }

        // This week not being logged yet shouldn't break a live streak.
        var streak = 0
        if !weeks.contains(cursor), let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) {
            cursor = previous
        }
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    static func lifetimeVolume(for sessions: [WorkoutSession]) -> Double {
        sessions.filter { $0.endedAt != nil }.reduce(0) { $0 + $1.volumeKg }
    }

    /// Exercises the athlete actually uses, most recent first.
    static func recentExerciseNames(in sessions: [WorkoutSession], limit: Int = 6) -> [String] {
        var seen: [String] = []
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            for block in session.orderedBlocks where !seen.contains(block.name) {
                seen.append(block.name)
                if seen.count >= limit { return seen }
            }
        }
        return seen
    }
}

// MARK: - Milestones

/// Thresholds that feel worth celebrating without becoming confetti spam.
enum MilestoneThresholds {
    static let sessionCounts: [Int] = [1, 5, 10, 25, 50, 100, 200, 365, 500, 1000]
    static let streaks: [Int] = [2, 4, 8, 12, 26, 52]
    static let lifetimeVolumeKg: [Double] = [10_000, 50_000, 100_000, 250_000, 500_000, 1_000_000]
}

struct MilestoneAward: Identifiable, Equatable {
    let id = UUID()
    let kind: MilestoneKind
    let exerciseName: String
    let value: Double
    let previousValue: Double
}

@MainActor
struct MilestoneEngine {
    let context: ModelContext
    let athlete: Athlete

    /// Existing record value for a kind, falling back to the session history when
    /// no milestone has been written yet (so importing history can't fake a PR).
    private func currentRecord(kind: MilestoneKind, exerciseName: String) -> Double {
        athlete.allMilestones
            .filter { $0.kind == kind && $0.exerciseName == exerciseName }
            .map(\.value)
            .max() ?? 0
    }

    /// Evaluates one freshly completed set. Returns anything newly earned.
    func evaluate(set: SetRecord, block: ExerciseBlock, session: WorkoutSession) -> [MilestoneAward] {
        guard set.isComplete, !set.isWarmup else { return [] }
        let name = block.name
        guard !name.isEmpty else { return [] }

        let history = Stats.bests(for: name, in: athlete.allSessions, excluding: session.id)
        var awards: [MilestoneAward] = []

        func consider(_ kind: MilestoneKind, value: Double, historyBaseline: Double) {
            guard value > 0 else { return }
            let baseline = max(historyBaseline, currentRecord(kind: kind, exerciseName: name))
            // First-ever entries are recorded silently; only genuine improvements surface.
            guard baseline > 0, value > baseline + 0.001 else {
                if baseline == 0 { write(kind, name: name, value: value, previous: 0) }
                return
            }
            write(kind, name: name, value: value, previous: baseline)
            awards.append(
                MilestoneAward(kind: kind, exerciseName: name, value: value, previousValue: baseline)
            )
        }

        switch block.tracking {
        case .weightAndReps:
            consider(.heaviestSet, value: set.weightKg, historyBaseline: history.heaviestKg)
            consider(.estimatedMax, value: set.estimatedOneRepMaxKg, historyBaseline: history.estimatedMaxKg)
        case .repsOnly:
            consider(.repRecord, value: Double(set.reps), historyBaseline: Double(history.bestReps))
        case .duration:
            consider(.repRecord, value: Double(set.seconds), historyBaseline: Double(history.bestReps))
        }

        return awards
    }

    /// Evaluates the session-level records once a workout is finished.
    func evaluateFinish(session: WorkoutSession) -> [MilestoneAward] {
        var awards: [MilestoneAward] = []
        let completed = athlete.completedSessions

        // Per-exercise session volume.
        for block in session.orderedBlocks where block.volumeKg > 0 {
            let name = block.name
            let history = Stats.bests(for: name, in: athlete.allSessions, excluding: session.id)
            let baseline = max(history.bestSessionVolumeKg, currentRecord(kind: .volumeRecord, exerciseName: name))
            if baseline > 0, block.volumeKg > baseline + 0.001 {
                write(.volumeRecord, name: name, value: block.volumeKg, previous: baseline)
                awards.append(.init(kind: .volumeRecord, exerciseName: name, value: block.volumeKg, previousValue: baseline))
            } else if baseline == 0 {
                write(.volumeRecord, name: name, value: block.volumeKg, previous: 0)
            }
        }

        // Session count badges.
        let count = completed.count
        if MilestoneThresholds.sessionCounts.contains(count),
           currentRecord(kind: .sessionCount, exerciseName: "") < Double(count) {
            write(.sessionCount, name: "", value: Double(count), previous: currentRecord(kind: .sessionCount, exerciseName: ""))
            awards.append(.init(kind: .sessionCount, exerciseName: "", value: Double(count), previousValue: 0))
        }

        // Streak badges.
        let streak = Stats.weekStreak(for: completed)
        if MilestoneThresholds.streaks.contains(streak),
           currentRecord(kind: .streak, exerciseName: "") < Double(streak) {
            write(.streak, name: "", value: Double(streak), previous: currentRecord(kind: .streak, exerciseName: ""))
            awards.append(.init(kind: .streak, exerciseName: "", value: Double(streak), previousValue: 0))
        }

        // Lifetime tonnage badges.
        let lifetime = Stats.lifetimeVolume(for: completed)
        let logged = currentRecord(kind: .lifetimeVolume, exerciseName: "")
        if let crossed = MilestoneThresholds.lifetimeVolumeKg.last(where: { lifetime >= $0 && logged < $0 }) {
            write(.lifetimeVolume, name: "", value: crossed, previous: logged)
            awards.append(.init(kind: .lifetimeVolume, exerciseName: "", value: crossed, previousValue: logged))
        }

        return awards
    }

    private func write(_ kind: MilestoneKind, name: String, value: Double, previous: Double) {
        let milestone = Milestone(
            kind: kind,
            exerciseName: name,
            value: value,
            previousValue: previous,
            athlete: athlete
        )
        context.insert(milestone)
    }
}

// MARK: - Training split

/// Weekly hard-set counts per muscle group — the number most programmes are
/// actually written against, and the one thing volume in kilograms can't tell
/// you (10 000 kg of leg press is not 10 000 kg of lateral raises).
extension Stats {
    struct MuscleLoad: Identifiable, Equatable {
        var id: String { muscle.rawValue }
        let muscle: MuscleGroup
        let sets: Int
        let volumeKg: Double
    }

    static func muscleSplit(
        for sessions: [WorkoutSession],
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [MuscleLoad] {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: .now) else { return [] }
        var sets: [MuscleGroup: Int] = [:]
        var volume: [MuscleGroup: Double] = [:]

        for session in sessions where session.endedAt != nil && session.startedAt >= cutoff {
            for block in session.allBlocks {
                guard let muscle = block.exercise?.muscle else { continue }
                let counted = block.allSets.filter { $0.isComplete && $0.kind.countsTowardVolume }
                guard !counted.isEmpty else { continue }
                sets[muscle, default: 0] += counted.count
                volume[muscle, default: 0] += counted.reduce(0) { $0 + $1.volumeKg }
            }
        }

        return sets
            .map { MuscleLoad(muscle: $0.key, sets: $0.value, volumeKg: volume[$0.key] ?? 0) }
            .sorted { $0.sets > $1.sets }
    }

    /// Sets logged per day, oldest first, starting on a Monday so the grid's
    /// rows line up with weekdays the way a calendar does.
    static func dailyLoad(
        for sessions: [WorkoutSession],
        weeks: Int = 17,
        calendar: Calendar = .current
    ) -> [(day: Date, sets: Int)] {
        var calendar = calendar
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: .now)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [] }

        var counts: [Date: Int] = [:]
        for session in sessions where session.endedAt != nil {
            let day = calendar.startOfDay(for: session.startedAt)
            counts[day, default: 0] += session.workingSets.count
        }

        return (0..<(weeks * 7)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            // Days still to come this week stay blank rather than being dropped,
            // so the block keeps its shape.
            return (day: day, sets: day > today ? 0 : (counts[day] ?? 0))
        }
    }

    /// Longest run of consecutive *days* with a session — the streak people brag
    /// about, kept separate from the week streak used for milestones.
    static func bestDayStreak(for sessions: [WorkoutSession], calendar: Calendar = .current) -> Int {
        let days = Set(sessions.filter { $0.endedAt != nil }.map { calendar.startOfDay(for: $0.startedAt) })
        var best = 0
        for day in days {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day), !days.contains(previous) else {
                continue // not the start of a run
            }
            var length = 0
            var cursor = day
            while days.contains(cursor) {
                length += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            best = max(best, length)
        }
        return best
    }
}

// MARK: - Progression

enum Progression {
    /// The next sensible target for an exercise: repeat the top set, or nudge the
    /// load once the rep target was cleared. Deliberately conservative — it
    /// suggests, it doesn't program.
    static func suggestion(
        for bests: ExerciseBests,
        tracking: TrackingStyle,
        unit: WeightUnit,
        repTarget: Int = 8
    ) -> String? {
        guard let last = bests.lastSet else { return nil }
        switch tracking {
        case .weightAndReps:
            guard last.weightKg > 0 else { return nil }
            if last.reps >= repTarget {
                let next = last.weightKg + unit.toKilograms(unit.step)
                return "Try \(Format.weight(next, in: unit))\(unit.short) × \(max(1, last.reps - 2))"
            }
            return "Try \(Format.weight(last.weightKg, in: unit))\(unit.short) × \(last.reps + 1)"
        case .repsOnly:
            return "Try \(last.reps + 1) reps"
        case .duration:
            return "Try \(last.seconds + 5)s"
        }
    }
}
