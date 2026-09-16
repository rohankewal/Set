#if DEBUG
import Foundation
import SwiftData

/// Debug-only fixtures. Launch with `--demo` to fill the store with a few weeks
/// of plausible training so the screens can be reviewed with real content.
/// Never compiled into a release build.
enum DemoData {
    @MainActor
    static func installIfRequested(context: ModelContext, settings: AppSettings) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--demo") else { return }

        // Start from a clean slate so repeated launches are deterministic.
        for athlete in (try? context.fetch(FetchDescriptor<Athlete>())) ?? [] {
            context.delete(athlete)
        }

        let athlete = Athlete(name: "Rohan", bodyweightKg: 78)
        context.insert(athlete)
        settings.selectedAthleteID = athlete.id

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        func exercise(_ name: String) -> Exercise? { exercises.first { $0.name == name } }

        let plan: [(String, [(Double, Int)])] = [
            ("Back Squat", [(80, 5), (95, 5), (105, 5)]),
            ("Bench Press", [(60, 8), (70, 6), (75, 5)]),
            ("Barbell Row", [(60, 8), (65, 8), (65, 7)]),
            ("Pull-Up", [(0, 9), (0, 8), (0, 7)])
        ]

        let calendar = Calendar.current
        for week in stride(from: 7, through: 0, by: -1) {
            for dayOffset in [0, 3] {
                let daysAgo = week * 7 + dayOffset
                guard daysAgo > 0,
                      let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now)
                else { continue }

                let session = WorkoutSession(
                    title: dayOffset == 0 ? "Lower + Push" : "Upper Pull",
                    athlete: athlete,
                    startedAt: date
                )
                session.endedAt = date.addingTimeInterval(58 * 60)
                context.insert(session)

                // Light linear progression, so charts and records have a shape.
                let progression = Double(7 - week) * 2.5
                for (order, entry) in plan.enumerated() {
                    guard let model = exercise(entry.0) else { continue }
                    let block = ExerciseBlock(exercise: model, order: order, restSeconds: 120)
                    block.session = session
                    context.insert(block)

                    for (index, set) in entry.1.enumerated() {
                        let record = SetRecord(
                            index: index,
                            weightKg: set.0 > 0 ? set.0 + progression : 0,
                            reps: set.1 + (week < 3 ? 1 : 0),
                            kind: index == 0 && order < 2 ? .warmup : .working
                        )
                        record.isComplete = true
                        record.completedAt = date.addingTimeInterval(Double(order * 600 + index * 150))
                        record.block = block
                        context.insert(record)
                    }
                }

                let engine = MilestoneEngine(context: context, athlete: athlete)
                _ = engine.evaluateFinish(session: session)
                for block in session.orderedBlocks {
                    for set in block.orderedSets {
                        _ = engine.evaluate(set: set, block: block, session: session)
                    }
                }
            }
        }

        // A routine lifted off the most recent session, plus a body-weight trend.
        if let latest = athlete.completedSessions.first {
            let routine = Routine(name: "Lower + Push", athlete: athlete)
            context.insert(routine)
            for block in latest.orderedBlocks {
                let item = RoutineItem(
                    exercise: block.exercise,
                    order: block.order,
                    targetSets: max(1, block.orderedSets.count),
                    targetReps: block.orderedSets.last?.reps ?? 8,
                    targetWeightKg: block.orderedSets.map(\.weightKg).max(),
                    restSeconds: block.restSeconds
                )
                item.routine = routine
                context.insert(item)
            }
            routine.useCount = 4
            routine.lastUsedAt = latest.startedAt
        }

        for week in stride(from: 8, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -week * 7, to: .now) else { continue }
            context.insert(
                BodyEntry(date: date, weightKg: 78 + Double(8 - week) * 0.35, athlete: athlete)
            )
        }
        athlete.bodyweightKg = 80.8

        context.saveChanges()
    }

    /// Reproduces what sync actually does on a second device: the same library
    /// movements and the same athlete arrive again with different ids, and a
    /// session logged "over there" points at the duplicates.
    @MainActor
    static func injectSyncDuplicates(context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let athletes = (try? context.fetch(FetchDescriptor<Athlete>())) ?? []
        guard let original = athletes.first else { return }

        // A second copy of the athlete, as a second device's bootstrap would make.
        let twin = Athlete(name: original.name)
        twin.createdAt = original.createdAt.addingTimeInterval(60)
        context.insert(twin)

        var duplicated: [Exercise] = []
        for name in ["Back Squat", "Bench Press", "Deadlift"] {
            guard let source = exercises.first(where: { $0.name == name }) else { continue }
            let copy = Exercise(
                name: source.name,
                muscle: source.muscle,
                equipment: source.equipment,
                tracking: source.tracking
            )
            copy.createdAt = source.createdAt.addingTimeInterval(60)
            context.insert(copy)
            duplicated.append(copy)
        }

        // History on the twin, referencing the duplicate movements.
        let session = WorkoutSession(title: "Synced From Elsewhere", athlete: twin)
        session.endedAt = .now
        context.insert(session)
        for (order, exercise) in duplicated.enumerated() {
            let block = ExerciseBlock(exercise: exercise, order: order)
            block.session = session
            context.insert(block)
            let record = SetRecord(index: 0, weightKg: 100, reps: 5)
            record.isComplete = true
            record.completedAt = .now
            record.block = block
            context.insert(record)
        }

        context.saveChanges()
        NSLog("DEDUPE fixture: athletes=%d exercises=%d", athletes.count + 1, exercises.count + duplicated.count)
    }

    /// Runs the merge and reports what survived, so the behaviour is checked
    /// rather than assumed.
    @MainActor
    static func verifyDeduplication(context: ModelContext) {
        let merged = Deduplicator.run(in: context, deep: true)
        let athletes = (try? context.fetch(FetchDescriptor<Athlete>())) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let blocks = (try? context.fetch(FetchDescriptor<ExerciseBlock>())) ?? []
        let orphaned = blocks.filter { $0.exercise == nil }.count
        let carried = athletes.first?.allSessions.contains { $0.title == "Synced From Elsewhere" } ?? false
        NSLog(
            "DEDUPE result: merged=%d athletes=%d exercises=%d orphanedBlocks=%d historyCarriedOver=%@",
            merged, athletes.count, exercises.count, orphaned, carried ? "yes" : "no"
        )
    }
}
#endif
