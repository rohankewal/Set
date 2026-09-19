import Foundation
import Observation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Owns the in-progress workout: mutations, the rest clock, and milestone
/// detection. Views stay declarative and never touch the model context directly
/// while a workout is running.
@Observable
final class WorkoutEngine {
    // MARK: State

    private(set) var session: WorkoutSession?
    /// Wall-clock end of the current rest period. `nil` means "not counting" —
    /// either idle, or paused with the remainder parked in `restPausedRemaining`.
    private(set) var restEndsAt: Date?
    /// Seconds left on a paused rest. Non-nil only while paused.
    private(set) var restPausedRemaining: TimeInterval?
    private(set) var restTotal: Int = 90
    /// Newly earned records waiting to be shown as a banner.
    var pendingAwards: [MilestoneAward] = []
    /// Set just marked done — used to drive the row's flash animation.
    private(set) var lastCompletedSetID: UUID?
    /// Non-nil right after finishing, so the summary sheet has something to show.
    var finishedSession: WorkoutSession?
    /// Everything earned during the current workout, banner-consumed or not, so
    /// the summary can recap the lot.
    private(set) var sessionAwards: [MilestoneAward] = []
    /// Records to show on the summary sheet. Kept apart from `pendingAwards` so
    /// the banner queue can't consume them before the summary appears.
    private(set) var finishedAwards: [MilestoneAward] = []

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let liveActivity = LiveActivityController()
    /// Set by the app once both exist; used to mirror state to the watch.
    @ObservationIgnored weak var watch: PhoneWatchLink?

    /// The exercise you're on, shared by Focus mode and the watch. Held by
    /// identity rather than position, so reordering exercises doesn't quietly
    /// point it at a different one. It follows what you do: adding an
    /// exercise or logging a set moves it there.
    private(set) var focusedBlockID: UUID?

    /// The exercise currently in focus, defaulting to the first unfinished one.
    var focusedBlock: ExerciseBlock? {
        guard let session else { return nil }
        let blocks = session.orderedBlocks
        guard !blocks.isEmpty else { return nil }
        if let focusedBlockID, let block = blocks.first(where: { $0.id == focusedBlockID }) { return block }
        return blocks.first { !$0.isFinished } ?? blocks.first
    }

    /// Position of the focused exercise, for pagers.
    var focusIndex: Int {
        guard let session, let block = focusedBlock else { return 0 }
        return session.orderedBlocks.firstIndex(of: block) ?? 0
    }

    /// The set to log next in the focused exercise.
    var focusedSet: SetRecord? {
        guard let block = focusedBlock else { return nil }
        return block.orderedSets.first { !$0.isComplete } ?? block.orderedSets.last
    }

    func moveFocus(by delta: Int) {
        guard let session else { return }
        let blocks = session.orderedBlocks
        guard !blocks.isEmpty else { return }
        focus(on: blocks[min(max(focusIndex + delta, 0), blocks.count - 1)])
        Haptics.play(.tick)
    }

    func focus(on block: ExerciseBlock) {
        guard focusedBlockID != block.id else { return }
        focusedBlockID = block.id
        watch?.publish()
    }

    init(context: ModelContext, settings: AppSettings) {
        self.context = context
        self.settings = settings
    }

    var isRunning: Bool { session != nil }

    /// Counting down right now.
    var isResting: Bool {
        guard let restEndsAt else { return false }
        return restEndsAt > .now
    }

    var isRestPaused: Bool { restPausedRemaining != nil }

    /// A rest period exists, running or held.
    var isRestActive: Bool { isResting || isRestPaused }

    var restRemaining: TimeInterval {
        if let paused = restPausedRemaining { return paused }
        guard let restEndsAt else { return 0 }
        return max(0, restEndsAt.timeIntervalSinceNow)
    }

    var restProgress: Double {
        guard restTotal > 0, isRestActive else { return 0 }
        return min(1, max(0, 1 - restRemaining / Double(restTotal)))
    }

    // MARK: Lifecycle

    /// Re-attaches to a workout that was left running (app relaunch, crash, reboot).
    func restoreIfNeeded() {
        guard session == nil, let id = settings.activeSessionID else { return }
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let found = try? context.fetch(descriptor).first, found.isActive else {
            settings.activeSessionID = nil
            return
        }
        session = found
        applyScreenPolicy()
    }

    @discardableResult
    func start(for athlete: Athlete?, title: String? = nil) -> WorkoutSession {
        let session = WorkoutSession(title: title ?? Self.suggestedTitle(), athlete: athlete)
        context.insert(session)
        self.session = session
        settings.activeSessionID = session.id
        sessionAwards = []
        pendingAwards = []
        focusedBlockID = nil
        save()
        applyScreenPolicy()
        Haptics.play(.complete)
        return session
    }

    /// Starts a workout pre-filled with the same exercises as a previous one.
    @discardableResult
    func repeatSession(_ template: WorkoutSession, for athlete: Athlete?) -> WorkoutSession {
        let session = start(for: athlete, title: template.title)
        for block in template.orderedBlocks {
            guard let exercise = block.exercise else { continue }
            let new = addExercise(exercise)
            new?.restSeconds = block.restSeconds
            // Seed the same set count with last time's numbers, unchecked.
            let templateSets = block.orderedSets.filter { $0.isComplete }
            if templateSets.count > 1, let new {
                for extra in templateSets.dropFirst() {
                    let record = SetRecord(
                        index: new.allSets.count,
                        weightKg: extra.weightKg,
                        reps: extra.reps,
                        seconds: extra.seconds,
                        kind: extra.kind
                    )
                    record.block = new
                    context.insert(record)
                }
            }
        }
        // Built with addExercise, which moves focus to each new exercise;
        // a repeated workout starts at the top.
        focusedBlockID = nil
        save()
        return session
    }

    func finish() {
        guard let session else { return }
        prune(session)

        session.endedAt = .now
        if let athlete = session.athlete {
            let engine = MilestoneEngine(context: context, athlete: athlete)
            finishedAwards = sessionAwards + engine.evaluateFinish(session: session)
        } else {
            finishedAwards = sessionAwards
        }
        pendingAwards.removeAll()
        sessionAwards = []
        settings.activeSessionID = nil
        endRest()
        save()

        finishedSession = session
        self.session = nil
        applyScreenPolicy()
        Haptics.play(.record)
    }

    func discard() {
        guard let session else { return }
        context.delete(session)
        settings.activeSessionID = nil
        sessionAwards = []
        pendingAwards = []
        self.session = nil
        endRest()
        save()
        applyScreenPolicy()
        Haptics.play(.warning)
    }

    /// Drops sets that were never completed and exercises left untouched, so the
    /// saved history is exactly what happened.
    private func prune(_ session: WorkoutSession) {
        for block in session.allBlocks {
            for set in block.allSets where !set.isComplete {
                context.delete(set)
            }
            if block.allSets.allSatisfy({ !$0.isComplete }) {
                context.delete(block)
            }
        }
    }

    // MARK: Exercises

    @discardableResult
    func addExercise(_ exercise: Exercise) -> ExerciseBlock? {
        guard let session else { return nil }
        let block = ExerciseBlock(
            exercise: exercise,
            order: (session.allBlocks.map(\.order).max() ?? -1) + 1,
            restSeconds: settings.defaultRestSeconds
        )
        block.session = session
        context.insert(block)
        addSet(to: block)
        // A newly added exercise is the one you're about to do.
        focusedBlockID = block.id
        save()
        Haptics.play(.tick)
        return block
    }

    func remove(_ block: ExerciseBlock) {
        context.delete(block)
        save()
    }

    /// Applies a new order from a drag interaction.
    func reorder(_ blocks: [ExerciseBlock]) {
        for (offset, block) in blocks.enumerated() {
            block.order = offset
        }
        save()
    }

    // MARK: Sets

    @discardableResult
    func addSet(to block: ExerciseBlock, kind: SetKind = .working) -> SetRecord {
        let prefill = prefillValues(for: block)
        let record = SetRecord(
            index: (block.allSets.map(\.index).max() ?? -1) + 1,
            weightKg: prefill.weightKg,
            reps: prefill.reps,
            seconds: prefill.seconds,
            kind: kind
        )
        record.block = block
        context.insert(record)
        save()
        return record
    }

    func remove(_ set: SetRecord, from block: ExerciseBlock) {
        context.delete(set)
        // Keep indices contiguous so the numbering never gains a gap.
        for (offset, remaining) in block.orderedSets.filter({ $0.id != set.id }).enumerated() {
            remaining.index = offset
        }
        save()
    }

    /// Best guess for a fresh set: repeat this session's last set, else last
    /// time's top set, else empty.
    private func prefillValues(for block: ExerciseBlock) -> (weightKg: Double, reps: Int, seconds: Int) {
        if let last = block.orderedSets.last(where: { $0.kind != .warmup }) ?? block.orderedSets.last {
            return (last.weightKg, last.reps, last.seconds)
        }
        guard let athlete = session?.athlete else { return (0, 0, 0) }
        let history = Stats.bests(for: block.name, in: athlete.allSessions, excluding: session?.id)
        if let last = history.lastSet {
            return (last.weightKg, last.reps, last.seconds)
        }
        return (0, 0, block.tracking == .duration ? 30 : 0)
    }

    func toggleCompletion(of set: SetRecord, in block: ExerciseBlock) {
        if set.isComplete {
            set.isComplete = false
            set.completedAt = nil
            save()
            Haptics.play(.tick)
            return
        }

        guard isLoggable(set, tracking: block.tracking) else {
            Haptics.play(.warning)
            return
        }

        set.isComplete = true
        set.completedAt = .now
        lastCompletedSetID = set.id
        focusedBlockID = block.id
        Haptics.play(.complete)

        if let session, let athlete = session.athlete {
            let engine = MilestoneEngine(context: context, athlete: athlete)
            let awards = engine.evaluate(set: set, block: block, session: session)
            if !awards.isEmpty {
                pendingAwards.append(contentsOf: awards)
                sessionAwards.append(contentsOf: awards)
                Haptics.play(.record)
            }
        }

        save()

        // Warm-ups don't earn a rest, and inside a superset only the last
        // exercise does — that's the whole point of pairing them.
        if settings.autoStartRest,
           set.kind != .warmup,
           block.isLastInSuperset(of: session) {
            startRest(seconds: block.restSeconds, exercise: block.name)
        }
    }

    // MARK: Supersets

    /// Pairs (or triples) exercises so they're performed back-to-back.
    func groupSuperset(_ blocks: [ExerciseBlock]) {
        guard let session, blocks.count > 1 else { return }
        let used = Set(session.allBlocks.compactMap(\.supersetGroup))
        let group = (used.max() ?? 0) + 1
        // Keep the group contiguous so the bracket in the UI reads correctly.
        var ordered = session.orderedBlocks.filter { !blocks.contains($0) }
        let insertAt = min(blocks.compactMap { session.orderedBlocks.firstIndex(of: $0) }.min() ?? 0, ordered.count)
        for block in blocks { block.supersetGroup = group }
        ordered.insert(contentsOf: blocks, at: insertAt)
        reorder(ordered)
        Haptics.play(.complete)
    }

    func ungroupSuperset(_ block: ExerciseBlock) {
        guard let session, let group = block.supersetGroup else { return }
        for peer in session.allBlocks where peer.supersetGroup == group {
            peer.supersetGroup = nil
        }
        save()
        Haptics.play(.tick)
    }

    // MARK: Warm-ups

    /// Inserts a standard ramp below the first working set: 40 / 55 / 70 / 85%
    /// of the target load. Existing warm-ups are replaced, not stacked.
    func addWarmupSets(to block: ExerciseBlock) {
        let target = block.orderedSets.first(where: { $0.kind == .working })?.weightKg
            ?? prefillValues(for: block).weightKg
        guard target > 0 else { Haptics.play(.warning); return }

        for existing in block.allSets where existing.kind == .warmup && !existing.isComplete {
            context.delete(existing)
        }

        let ramp: [(Double, Int)] = [(0.4, 5), (0.55, 5), (0.7, 3), (0.85, 2)]
        let bar = settings.barWeightKg
        var warmups: [SetRecord] = []
        for (fraction, reps) in ramp {
            let raw = target * fraction
            // Never prescribe less than the empty bar for barbell work.
            let rounded = PlateMath.round(raw, to: settings.unit, minimum: block.equipmentUsesBar ? bar : 0)
            guard rounded < target else { continue }
            if let last = warmups.last, abs(last.weightKg - rounded) < 0.01 { continue }
            let record = SetRecord(index: 0, weightKg: rounded, reps: reps, kind: .warmup)
            record.block = block
            context.insert(record)
            warmups.append(record)
        }

        // Warm-ups first, then everything that was already there.
        var index = 0
        for record in warmups {
            record.index = index
            index += 1
        }
        for record in block.orderedSets where record.kind != .warmup {
            record.index = index
            index += 1
        }
        save()
        Haptics.play(.complete)
    }

    // MARK: Routines

    /// Starts a workout pre-built from a saved routine.
    @discardableResult
    func start(routine: Routine, for athlete: Athlete?) -> WorkoutSession {
        let session = start(for: athlete, title: routine.name)
        for item in routine.orderedItems {
            guard let exercise = item.exercise else { continue }
            let block = ExerciseBlock(exercise: exercise, order: item.order, restSeconds: item.restSeconds)
            block.supersetGroup = item.supersetGroup
            block.session = session
            context.insert(block)

            let history = athlete.map { Stats.bests(for: exercise.name, in: $0.allSessions) }
            for index in 0..<max(1, item.targetSets) {
                let weight = item.targetWeightKg ?? history?.lastSet?.weightKg ?? 0
                let record = SetRecord(
                    index: index,
                    weightKg: weight,
                    reps: item.targetReps,
                    seconds: exercise.tracking == .duration ? item.targetReps : 0
                )
                record.block = block
                context.insert(record)
            }
        }
        routine.lastUsedAt = .now
        routine.useCount += 1
        save()
        return session
    }

    /// Captures a finished (or in-progress) session as a reusable routine.
    @discardableResult
    func saveAsRoutine(_ session: WorkoutSession, named name: String, for athlete: Athlete?) -> Routine {
        let routine = Routine(name: name, athlete: athlete ?? session.athlete)
        context.insert(routine)
        for block in session.orderedBlocks {
            let completed = block.orderedSets.filter { $0.isComplete && $0.kind.countsTowardVolume }
            let item = RoutineItem(
                exercise: block.exercise,
                order: block.order,
                targetSets: max(1, completed.count),
                targetReps: completed.last?.reps ?? 8,
                targetWeightKg: completed.map(\.weightKg).max(),
                restSeconds: block.restSeconds,
                supersetGroup: block.supersetGroup
            )
            item.routine = routine
            context.insert(item)
        }
        save()
        Haptics.play(.record)
        return routine
    }

    // MARK: Body weight

    func logBodyWeight(_ weightKg: Double, for athlete: Athlete?, on date: Date = .now) {
        guard weightKg > 0 else { return }
        let calendar = Calendar.current
        // One reading per day: a second entry replaces the first.
        if let existing = athlete?.allBodyEntries.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            existing.weightKg = weightKg
        } else {
            context.insert(BodyEntry(date: date, weightKg: weightKg, athlete: athlete))
        }
        athlete?.bodyweightKg = weightKg
        save()
        Haptics.play(.complete)
    }

    private func isLoggable(_ set: SetRecord, tracking: TrackingStyle) -> Bool {
        switch tracking {
        case .weightAndReps: set.reps > 0
        case .repsOnly: set.reps > 0
        case .duration: set.seconds > 0
        }
    }

    // MARK: Rest clock

    func startRest(seconds: Int, exercise: String = "") {
        guard seconds > 0 else { return }
        restTotal = seconds
        restPausedRemaining = nil
        let end = Date.now.addingTimeInterval(Double(seconds))
        restEndsAt = end
        if settings.restAlertsEnabled {
            let target = Double(seconds)
            Task { await RestAlerts.schedule(in: target, exercise: exercise) }
        }
        watch?.publish()
        liveActivity.start(
            sessionTitle: session?.title ?? "Workout",
            endsAt: end,
            total: Double(seconds),
            setsLogged: session?.completedSets.count ?? 0,
            nextUp: nextUpDescription()
        )
    }

    /// "Back Squat · 120kg × 5" — what the Lock Screen should say is coming.
    private func nextUpDescription() -> String {
        guard let session else { return "" }
        let pending = session.orderedBlocks
            .first { block in block.allSets.contains { !$0.isComplete } }
        guard let block = pending,
              let set = block.orderedSets.first(where: { !$0.isComplete }) else {
            return "Last set logged"
        }
        switch block.tracking {
        case .weightAndReps:
            return "\(block.name) · \(Format.weight(set.weightKg, in: settings.unit))\(settings.unit.short) × \(set.reps)"
        case .repsOnly:
            return "\(block.name) · \(set.reps) reps"
        case .duration:
            return "\(block.name) · \(set.seconds)s"
        }
    }

    private func refreshLiveActivity() {
        watch?.publish()
        liveActivity.update(
            endsAt: restEndsAt,
            remaining: restRemaining,
            total: Double(restTotal),
            isPaused: isRestPaused,
            setsLogged: session?.completedSets.count ?? 0,
            nextUp: nextUpDescription()
        )
    }

    /// Hold the clock where it is. The remainder is parked rather than recomputed,
    /// so a long pause between sets can't quietly expire the timer.
    func pauseRest() {
        guard let end = restEndsAt else { return }
        restPausedRemaining = max(0, end.timeIntervalSinceNow)
        restEndsAt = nil
        RestAlerts.cancel()
        refreshLiveActivity()
        Haptics.play(.tick)
    }

    func resumeRest() {
        guard let remaining = restPausedRemaining, remaining > 0 else {
            restPausedRemaining = nil
            return
        }
        restPausedRemaining = nil
        restEndsAt = Date.now.addingTimeInterval(remaining)
        if settings.restAlertsEnabled {
            Task { await RestAlerts.schedule(in: remaining, exercise: "") }
        }
        refreshLiveActivity()
        Haptics.play(.tick)
    }

    /// One control, three states: start / pause / resume.
    func toggleRest(defaultSeconds: Int? = nil, exercise: String = "") {
        if isResting {
            pauseRest()
        } else if isRestPaused {
            resumeRest()
        } else {
            startRest(seconds: defaultSeconds ?? settings.defaultRestSeconds, exercise: exercise)
        }
    }

    func adjustRest(by delta: Int) {
        if let paused = restPausedRemaining {
            restTotal = max(restTotal + delta, 15)
            restPausedRemaining = max(0, paused + Double(delta))
            refreshLiveActivity()
            Haptics.play(.tick)
            return
        }
        guard let current = restEndsAt else {
            startRest(seconds: max(15, settings.defaultRestSeconds + delta))
            return
        }
        let newEnd = current.addingTimeInterval(Double(delta))
        guard newEnd > .now else { endRest(); return }
        restTotal = max(restTotal + delta, 15)
        restEndsAt = newEnd
        if settings.restAlertsEnabled {
            let remaining = newEnd.timeIntervalSinceNow
            Task { await RestAlerts.schedule(in: remaining, exercise: "") }
        }
        refreshLiveActivity()
        Haptics.play(.tick)
    }

    func endRest() {
        restEndsAt = nil
        restPausedRemaining = nil
        RestAlerts.cancel()
        liveActivity.end()
        watch?.publish()
    }

    /// Called by the countdown view when it reaches zero.
    func restDidFinish() {
        guard restEndsAt != nil else { return }
        restEndsAt = nil
        liveActivity.end()
        Haptics.play(.record)
    }

    // MARK: Plumbing

    func clearFinished() {
        finishedAwards = []
        finishedSession = nil
    }

    func consumeAward() -> MilestoneAward? {
        pendingAwards.isEmpty ? nil : pendingAwards.removeFirst()
    }

    private func applyScreenPolicy() {
        #if canImport(UIKit) && !os(visionOS)
        UIApplication.shared.isIdleTimerDisabled = isRunning && settings.keepScreenAwake
        #endif
    }

    private func save() {
        watch?.publish()
        // Never interrupt a set with an alert — the failure is recorded and
        // surfaced as a banner, and the in-memory session carries on either way.
        context.saveChanges()
    }

    static func suggestedTitle(date: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<11: return "Morning Session"
        case 11..<15: return "Midday Session"
        case 15..<20: return "Evening Session"
        default: return "Late Session"
        }
    }
}
