#if DEBUG
import SwiftData
import SwiftUI

/// A standing check of the rules that are easy to break and awkward to test by
/// hand: when a tick starts, keeps or leaves a rest alone, that the clock
/// behaves the same wherever you are in the app, that it survives the app
/// being quit, and what happens to records when a logged set is corrected or
/// un-ticked. Runs against the real engine in throwaway workouts, which it
/// discards afterwards.
///
/// `--screen selftest`. DEBUG only, so it never ships.
@MainActor
enum SelfCheck {
    struct Line: Identifiable {
        let id = UUID()
        let passed: Bool
        let name: String
        let detail: String
    }

    private struct Fixture {
        let engine: WorkoutEngine
        let athlete: Athlete
        let block: ExerciseBlock
        let context: ModelContext
        let settings: AppSettings
    }

    static func run(context: ModelContext, settings: AppSettings) async -> [Line] {
        var lines: [Line] = []
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            lines.append(Line(passed: passed, name: name, detail: detail))
        }

        // The catch-up window is what makes two quick ticks one rest. Tests
        // drive it explicitly rather than waiting fifteen seconds.
        let window = WorkoutEngine.catchUpWindow
        defer { WorkoutEngine.catchUpWindow = window }

        // MARK: Starting and restarting

        var f = fixture(context: context, settings: settings)
        var set = f.block.orderedSets[0]
        f.engine.toggleCompletion(of: set, in: f.block)
        check("ticking a set starts the rest", f.engine.isRestActive)
        check("the rest is as long as the exercise asks for",
              abs(f.engine.restRemaining - Double(f.block.restSeconds)) < 1.5,
              "\(Int(f.engine.restRemaining))s of \(f.block.restSeconds)s")

        WorkoutEngine.catchUpWindow = 0 // as if the next tick came minutes later
        var next = f.engine.addSet(to: f.block); next.weightKg = 100; next.reps = 5
        var before = f.engine.restEndsAt
        f.engine.adjustRest(by: -30)
        f.engine.toggleCompletion(of: next, in: f.block)
        check("the next set in the same exercise restarts the rest",
              f.engine.restEndsAt != before && f.engine.isRestActive)

        before = f.engine.restEndsAt
        let second = f.engine.addExercise(exercise(context, "Second"))!
        let secondSet = second.orderedSets[0]; secondSet.weightKg = 60; secondSet.reps = 8
        f.engine.adjustRest(by: -30)
        f.engine.toggleCompletion(of: secondSet, in: second)
        check("a set on a new exercise restarts the rest",
              f.engine.restEndsAt != before && f.engine.isRestActive)

        // MARK: Ticks that shouldn't disturb a rest

        WorkoutEngine.catchUpWindow = 15
        f.engine.endRest()
        let warm = f.engine.addSet(to: f.block, kind: .warmup); warm.weightKg = 40; warm.reps = 5
        f.engine.toggleCompletion(of: warm, in: f.block)
        check("a warm-up starts no rest", !f.engine.isRestActive)

        f = fixture(context: context, settings: settings)
        let first = f.block.orderedSets[0]
        let later = f.engine.addSet(to: f.block); later.weightKg = 100; later.reps = 5
        f.engine.toggleCompletion(of: later, in: f.block)
        before = f.engine.restEndsAt
        f.engine.toggleCompletion(of: first, in: f.block)
        check("catching up on an earlier set leaves the rest alone",
              f.engine.restEndsAt == before)

        f = fixture(context: context, settings: settings)
        set = f.block.orderedSets[0]
        f.engine.toggleCompletion(of: set, in: f.block)
        before = f.engine.restEndsAt
        next = f.engine.addSet(to: f.block); next.weightKg = 100; next.reps = 5
        f.engine.toggleCompletion(of: next, in: f.block)
        check("two ticks moments apart are one rest", f.engine.restEndsAt == before)

        // …but only within the same exercise, and only while it's running.
        f = fixture(context: context, settings: settings)
        f.engine.toggleCompletion(of: f.block.orderedSets[0], in: f.block)
        before = f.engine.restEndsAt
        let other = f.engine.addExercise(exercise(context, "Other"))!
        let otherSet = other.orderedSets[0]; otherSet.weightKg = 50; otherSet.reps = 10
        f.engine.toggleCompletion(of: otherSet, in: other)
        check("a set on another exercise moments later still restarts the rest",
              f.engine.restEndsAt != before && f.engine.isRestActive)

        f = fixture(context: context, settings: settings)
        f.engine.toggleCompletion(of: f.block.orderedSets[0], in: f.block)
        f.engine.pauseRest()
        next = f.engine.addSet(to: f.block); next.weightKg = 100; next.reps = 5
        f.engine.toggleCompletion(of: next, in: f.block)
        check("logging while the rest is paused starts it running again",
              f.engine.isResting && !f.engine.isRestPaused)

        // MARK: Supersets

        f = fixture(context: context, settings: settings)
        let partner = f.engine.addExercise(exercise(context, "Partner"))!
        let partnerSet = partner.orderedSets[0]; partnerSet.weightKg = 30; partnerSet.reps = 12
        f.engine.groupSuperset([f.block, partner])
        f.engine.endRest()
        f.engine.toggleCompletion(of: f.block.orderedSets[0], in: f.block)
        check("the first exercise of a superset starts no rest", !f.engine.isRestActive)
        f.engine.toggleCompletion(of: partnerSet, in: partner)
        check("the last exercise of a superset starts the rest", f.engine.isRestActive)

        // MARK: The clock itself

        f = fixture(context: context, settings: settings)
        f.engine.startRest(seconds: 2)
        try? await Task.sleep(for: .milliseconds(2400))
        check("a rest finishes on its own, with no screen watching it",
              !f.engine.isRestActive && f.engine.restEndsAt == nil)

        f.engine.startRest(seconds: 60)
        f.engine.pauseRest()
        let held = f.engine.restRemaining
        try? await Task.sleep(for: .milliseconds(600))
        check("a paused rest holds its remainder", abs(f.engine.restRemaining - held) < 0.05,
              "\(Format.number(f.engine.restRemaining)) vs \(Format.number(held))")
        check("a paused rest still counts as resting", f.engine.isRestActive && !f.engine.isResting)
        f.engine.resumeRest()
        check("resuming picks up where it left off",
              f.engine.isResting && abs(f.engine.restRemaining - held) < 0.5)

        f.engine.adjustRest(by: 15)
        check("+15 adds fifteen seconds", abs(f.engine.restRemaining - (held + 15)) < 0.5)
        f.engine.adjustRest(by: -15)
        check("−15 takes them back", abs(f.engine.restRemaining - held) < 0.5)
        f.engine.endRest()
        check("skip clears the rest", !f.engine.isRestActive && f.engine.restEndsAt == nil)

        // MARK: Surviving the app closing

        f = fixture(context: context, settings: settings)
        f.engine.startRest(seconds: 120)
        let endsAt = f.engine.restEndsAt
        var reopened = WorkoutEngine(context: context, settings: settings)
        reopened.restoreIfNeeded()
        check("a rest survives the app being quit",
              reopened.isResting && reopened.restEndsAt == endsAt,
              reopened.restEndsAt.map { "ends \(Int($0.timeIntervalSinceNow))s from now" } ?? "no rest")

        f.engine.startRest(seconds: 1)
        try? await Task.sleep(for: .milliseconds(1200))
        reopened = WorkoutEngine(context: context, settings: settings)
        reopened.restoreIfNeeded()
        check("a rest that ran out while away doesn't come back",
              !reopened.isRestActive && reopened.restEndsAt == nil)

        f.engine.startRest(seconds: 90)
        f.engine.pauseRest()
        reopened = WorkoutEngine(context: context, settings: settings)
        reopened.restoreIfNeeded()
        check("a paused rest stays paused across a restart",
              reopened.isRestPaused && !reopened.isResting && abs(reopened.restRemaining - 90) < 1.5)

        // MARK: Finishing, discarding, correcting

        f = fixture(context: context, settings: settings)
        f.engine.toggleCompletion(of: f.block.orderedSets[0], in: f.block)
        f.engine.finish()
        check("finishing the workout clears the rest", !f.engine.isRestActive)

        f = fixture(context: context, settings: settings)
        f.engine.startRest(seconds: 90)
        f.engine.discard()
        check("discarding the workout clears the rest", !f.engine.isRestActive)

        f = fixture(context: context, settings: settings)
        set = f.block.orderedSets[0]
        f.engine.toggleCompletion(of: set, in: f.block)
        before = f.engine.restEndsAt
        set.reps = 3
        f.engine.setDidChange(set, in: f.block)
        check("correcting a logged set doesn't disturb the rest", f.engine.restEndsAt == before)
        f.engine.toggleCompletion(of: set, in: f.block)
        check("un-ticking a set doesn't disturb the rest", f.engine.restEndsAt == before)

        // MARK: Records

        f = fixture(context: context, settings: settings)
        let baseline = f.block.orderedSets[0]
        baseline.weightKg = 100; baseline.reps = 5
        f.engine.toggleCompletion(of: baseline, in: f.block)
        let baseRecord = f.athlete.allMilestones.filter { $0.kind == .estimatedMax }.map(\.value).max() ?? 0

        let big = f.engine.addSet(to: f.block); big.weightKg = 200; big.reps = 5
        f.engine.toggleCompletion(of: big, in: f.block)
        let inflated = big.estimatedOneRepMaxKg
        big.reps = 2
        f.engine.setDidChange(big, in: f.block)
        let values = f.athlete.allMilestones.filter { $0.kind == .estimatedMax }.map(\.value)
        check("a corrected set keeps its tick", big.isComplete)
        check("the record it no longer earned is withdrawn",
              !values.contains { abs($0 - inflated) < 0.01 }, "\(values.map { Format.number($0) })")
        check("the record matches the corrected set",
              abs((values.max() ?? 0) - big.estimatedOneRepMaxKg) < 0.01)
        check("an earlier set's record survives", values.contains { abs($0 - baseRecord) < 0.01 })

        let stamp = big.completedAt
        f.engine.toggleCompletion(of: big, in: f.block)
        check("un-ticking withdraws its records",
              f.athlete.allMilestones.filter { $0.achievedAt == stamp }.isEmpty)

        // MARK: Focus mode's current exercise

        f = fixture(context: context, settings: settings)
        let added = f.engine.addExercise(exercise(context, "Newest"))!
        check("adding an exercise makes it the one in focus", f.engine.focusedBlock?.id == added.id)
        f.engine.toggleCompletion(of: f.block.orderedSets[0], in: f.block)
        check("logging a set moves focus to that exercise", f.engine.focusedBlock?.id == f.block.id)
        f.engine.discard()

        cleanUp(context: context)
        return lines
    }

    // MARK: Fixtures

    private static func exercise(_ context: ModelContext, _ label: String) -> Exercise {
        let exercise = Exercise(name: "Check \(label) \(UUID().uuidString.prefix(4))", muscle: .legs, equipment: .barbell)
        context.insert(exercise)
        return exercise
    }

    private static func fixture(context: ModelContext, settings: AppSettings) -> Fixture {
        let athlete = Athlete(name: "Check \(UUID().uuidString.prefix(4))")
        context.insert(athlete)
        let engine = WorkoutEngine(context: context, settings: settings)
        engine.endRest()
        engine.start(for: athlete)
        let block = engine.addExercise(exercise(context, "Lift"))!
        let set = block.orderedSets[0]
        set.weightKg = 100
        set.reps = 5
        return Fixture(engine: engine, athlete: athlete, block: block, context: context, settings: settings)
    }

    private static func cleanUp(context: ModelContext) {
        for athlete in (try? context.fetch(FetchDescriptor<Athlete>())) ?? [] where athlete.name.hasPrefix("Check ") {
            context.delete(athlete)
        }
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] where exercise.name.hasPrefix("Check ") {
            context.delete(exercise)
        }
        context.saveChanges()
    }
}

struct SelfCheckView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var lines: [SelfCheck.Line] = []
    @State private var running = true

    private var failures: Int { lines.count { !$0.passed } }

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(running ? "Running…" : (failures == 0 ? "All \(lines.count) passed" : "\(failures) of \(lines.count) failed"))
                        .font(.system(size: 22, weight: .semibold))
                    ForEach(lines) { line in
                        Text("\(line.passed ? "PASS" : "FAIL")  \(line.name)\(line.detail.isEmpty ? "" : " — \(line.detail)")")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(line.passed ? Ink.secondary : Ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Metric.gutter)
            }
        }
        .task {
            lines = await SelfCheck.run(context: context, settings: settings)
            running = false
        }
    }
}
#endif
