import Foundation

/// Everything the coaching read is based on, computed deterministically in
/// Swift. No model is involved in producing a single number here — language
/// models are good at sentences and bad at arithmetic, so the arithmetic stays
/// where it can be tested.
struct TrainingDigest: Equatable, Sendable {
    /// Volume per minute of training, this block of sessions vs the one before.
    var density: Double = 0
    var densityChange: Double?
    /// Median seconds actually taken between working sets.
    var medianRest: Double?
    /// What the timers were set to over the same sets.
    var plannedRest: Double?
    var sessionsAnalysed: Int = 0
    var setsPerWeek: Int = 0
    var setsPerWeekChange: Int?
    /// Exercises whose estimated max hasn't moved in three or more sessions.
    var stalled: [Stall] = []
    /// Muscle groups with no sets in the last ten days.
    var stale: [MuscleGroup] = []
    var topMuscle: MuscleGroup?
    var weekStreak: Int = 0

    struct Stall: Equatable, Sendable, Identifiable {
        var id: String { exercise }
        let exercise: String
        let sessions: Int
        let changeKg: Double
    }

    var isEmpty: Bool { sessionsAnalysed == 0 }

    /// True when volume is climbing while strength isn't — the classic case for
    /// backing off rather than adding another set.
    var suggestsDeload: Bool {
        guard let setsChange = setsPerWeekChange else { return false }
        return !stalled.isEmpty && setsChange > 0
    }
}

enum Insights {
    /// Builds the digest from completed sessions. `window` is how many recent
    /// sessions count as "now"; the same number before that is the comparison.
    static func digest(
        for sessions: [WorkoutSession],
        window: Int = 5,
        calendar: Calendar = .current
    ) -> TrainingDigest {
        let completed = sessions
            .filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
        guard !completed.isEmpty else { return TrainingDigest() }

        var digest = TrainingDigest()
        digest.sessionsAnalysed = min(window, completed.count)

        let recent = Array(completed.prefix(window))
        let previous = Array(completed.dropFirst(window).prefix(window))

        digest.density = density(of: recent)
        if !previous.isEmpty {
            let before = density(of: previous)
            if before > 0 { digest.densityChange = (digest.density - before) / before }
        }

        let rests = restIntervals(in: recent)
        if !rests.isEmpty {
            digest.medianRest = median(rests.map(\.actual))
            digest.plannedRest = median(rests.map { Double($0.planned) })
        }

        digest.setsPerWeek = weeklySets(recent, calendar: calendar)
        if !previous.isEmpty {
            digest.setsPerWeekChange = digest.setsPerWeek - weeklySets(previous, calendar: calendar)
        }

        digest.stalled = stalls(in: completed)

        let split = Stats.muscleSplit(for: completed, days: 10, calendar: calendar)
        digest.topMuscle = split.first?.muscle
        let trained = Set(split.map(\.muscle))
        let tracked: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .legs, .glutes, .core]
        // Only call something stale if the athlete has trained it at some point.
        let everTrained = Set(
            completed.flatMap { $0.orderedBlocks.compactMap { $0.exercise?.muscle } }
        )
        digest.stale = tracked.filter { !trained.contains($0) && everTrained.contains($0) }

        digest.weekStreak = Stats.weekStreak(for: completed, calendar: calendar)
        return digest
    }

    /// Kilograms lifted per minute of session time.
    private static func density(of sessions: [WorkoutSession]) -> Double {
        let volume = sessions.reduce(0) { $0 + $1.volumeKg }
        let minutes = sessions.reduce(0.0) { $0 + max($1.duration / 60, 1) }
        guard minutes > 0 else { return 0 }
        return volume / minutes
    }

    /// Gap between consecutive completed working sets, paired with what the
    /// timer was set to. Gaps over 15 minutes are treated as breaks, not rest.
    private static func restIntervals(in sessions: [WorkoutSession]) -> [(actual: Double, planned: Int)] {
        var result: [(Double, Int)] = []
        for session in sessions {
            let sets = session.allBlocks
                .flatMap { block in block.allSets.map { (set: $0, block: block) } }
                .filter { $0.set.isComplete && $0.set.kind.countsTowardVolume }
                .compactMap { pair -> (date: Date, planned: Int)? in
                    guard let date = pair.set.completedAt else { return nil }
                    return (date, pair.block.restSeconds)
                }
                .sorted { $0.date < $1.date }

            for (previous, next) in zip(sets, sets.dropFirst()) {
                let gap = next.date.timeIntervalSince(previous.date)
                guard gap > 5, gap < 900 else { continue }
                result.append((gap, previous.planned))
            }
        }
        return result
    }

    private static func weeklySets(_ sessions: [WorkoutSession], calendar: Calendar) -> Int {
        guard let first = sessions.map(\.startedAt).min(),
              let last = sessions.map(\.startedAt).max() else { return 0 }
        let days = max(calendar.dateComponents([.day], from: first, to: last).day ?? 0, 1)
        let sets = sessions.reduce(0) { $0 + $1.workingSets.count }
        return Int((Double(sets) / Double(days) * 7).rounded())
    }

    /// An exercise counts as stalled when its best estimated max across the last
    /// three sessions is no better than the three before them.
    private static func stalls(in sessions: [WorkoutSession]) -> [TrainingDigest.Stall] {
        var byExercise: [String: [(date: Date, e1rm: Double)]] = [:]
        for session in sessions {
            for block in session.orderedBlocks {
                let best = block.allSets
                    .filter { $0.isComplete && $0.kind.countsTowardLoadRecords }
                    .map(\.estimatedOneRepMaxKg)
                    .max() ?? 0
                guard best > 0 else { continue }
                byExercise[block.name, default: []].append((session.startedAt, best))
            }
        }

        return byExercise.compactMap { name, points -> TrainingDigest.Stall? in
            let ordered = points.sorted { $0.date > $1.date }
            guard ordered.count >= 6 else { return nil }
            let recent = ordered.prefix(3).map(\.e1rm).max() ?? 0
            let older = ordered.dropFirst(3).prefix(3).map(\.e1rm).max() ?? 0
            guard older > 0, recent <= older + 0.01 else { return nil }
            return TrainingDigest.Stall(
                exercise: name,
                sessions: ordered.prefix(3).count,
                changeKg: recent - older
            )
        }
        .sorted { $0.changeKg < $1.changeKg }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
}

// MARK: - The read

/// What the app has decided is worth saying, decided in Swift. The claim and the
/// numbers backing it are fixed here; a model may only rephrase them.
struct TrainingRead: Equatable, Sendable {
    var headline: String
    var detail: String
    /// The only facts the claim rests on — also the only numbers a rewrite is
    /// allowed to use.
    var support: [String]
}

extension TrainingDigest {
    /// The read, written without a model. This is what ships on devices without
    /// Apple Intelligence, what shows instantly everywhere else, and the safety
    /// net if generation is rejected — the feature never depends on the model.
    func read(unit: WeightUnit) -> TrainingRead {
        if let stall = stalled.first, suggestsDeload, let setsChange = setsPerWeekChange {
            return TrainingRead(
                headline: "Volume up, strength flat",
                detail: "\(stall.exercise) hasn't moved in \(stall.sessions) sessions while weekly sets rose by \(setsChange). A lighter week often unsticks this.",
                support: [
                    "\(stall.exercise) estimated max: no gain across \(stall.sessions) sessions",
                    "Weekly working sets: \(setsPerWeek), up \(setsChange) on the previous block"
                ]
            )
        }
        if let stall = stalled.first {
            return TrainingRead(
                headline: "\(stall.exercise) has stalled",
                detail: "No improvement in estimated max across \(stall.sessions) sessions. Try changing reps, rest, or the variation before adding load.",
                support: ["\(stall.exercise) estimated max: no gain across \(stall.sessions) sessions"]
            )
        }
        if let change = densityChange, abs(change) > 0.1 {
            let percent = Int((abs(change) * 100).rounded())
            return TrainingRead(
                headline: "Density \(change > 0 ? "up" : "down") \(percent)%",
                detail: "You're moving \(Format.volume(density, in: unit)) \(unit.short) per minute across your last \(sessionsAnalysed) sessions, \(percent)% \(change > 0 ? "more" : "less") than the block before.",
                support: [
                    "Training density: \(Format.volume(density, in: unit)) \(unit.short) per minute",
                    "Density change vs the previous block: \(change > 0 ? "up" : "down") \(percent)%",
                    "Sessions analysed: \(sessionsAnalysed)"
                ]
            )
        }
        if let actual = medianRest, let planned = plannedRest, abs(actual - planned) > 30 {
            let delta = Int(abs(actual - planned))
            return TrainingRead(
                headline: actual > planned ? "Rests running long" : "Rests cut short",
                detail: "Median rest is \(Int(actual))s against \(Int(planned))s on the timer — \(delta)s \(actual > planned ? "over" : "under").",
                support: [
                    "Median rest taken: \(Int(actual)) seconds",
                    "Rest timer setting: \(Int(planned)) seconds"
                ]
            )
        }
        if let stale = stale.first {
            return TrainingRead(
                headline: "\(stale.label) is going stale",
                detail: "Nothing logged for \(stale.label.lowercased()) in the last ten days.",
                support: ["Muscle groups with no sets in ten days: \(self.stale.map(\.label).joined(separator: ", "))"]
            )
        }
        return TrainingRead(
            headline: "Steady",
            detail: "\(sessionsAnalysed) sessions analysed, around \(setsPerWeek) working sets a week. Nothing looks stuck.",
            support: [
                "Sessions analysed: \(sessionsAnalysed)",
                "Weekly working sets: \(setsPerWeek)",
                "Nothing detected as stalled"
            ]
        )
    }

    /// Everything computed, for the "show the working" disclosure. This is the
    /// audit trail, not the prompt.
    func factLines(unit: WeightUnit) -> [String] {
        var lines: [String] = []
        lines.append("Sessions analysed: \(sessionsAnalysed)")
        lines.append("Training density: \(Format.volume(density, in: unit)) \(unit.short) per minute")
        if let densityChange {
            lines.append("Density change vs previous block: \(Int((densityChange * 100).rounded()))%")
        }
        if let medianRest, let plannedRest {
            lines.append("Median rest taken: \(Int(medianRest))s against \(Int(plannedRest))s on the timer")
        }
        lines.append("Working sets per week: \(setsPerWeek)")
        if let setsPerWeekChange {
            lines.append("Change in weekly sets: \(setsPerWeekChange > 0 ? "+" : "")\(setsPerWeekChange)")
        }
        for stall in stalled.prefix(3) {
            lines.append("Stalled: \(stall.exercise), no gain over \(stall.sessions) sessions")
        }
        if !stale.isEmpty {
            lines.append("Not trained in 10 days: \(stale.map(\.label).joined(separator: ", "))")
        }
        if let topMuscle {
            lines.append("Most-trained muscle group: \(topMuscle.label)")
        }
        lines.append("Consecutive weeks trained: \(weekStreak)")
        return lines
    }
}
