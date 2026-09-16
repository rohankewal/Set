import Foundation
import SwiftData

/// Merges records that sync produced twice.
///
/// This is the price of CloudKit: unique constraints aren't supported, so
/// identity has to be enforced here instead. The case that actually happens is
/// mundane — install on a second device, it seeds its own copy of the 270-movement
/// library before the first device's copy arrives, and you end up with 540. The
/// same goes for the default "You" athlete.
///
/// Everything else is keyed on a UUID generated once at creation, so those can
/// only duplicate if the same record syncs back twice; they're swept by id as a
/// cheap safety net.
@MainActor
enum Deduplicator {
    /// - Parameter deep: also sweep every record by id. That means fetching all
    ///   sets — fine on launch, too expensive to repeat on every foreground once
    ///   someone has years of training logged, and pointless besides: id
    ///   collisions can only arrive with a sync, not with a screen unlock.
    @discardableResult
    static func run(in context: ModelContext, deep: Bool = false) -> Int {
        var merged = 0
        merged += mergeExercises(in: context)
        merged += mergeAthletes(in: context)
        if deep {
            merged += sweepDuplicateIDs(in: context)
        }
        if merged > 0 {
            context.saveChanges()
        }
        return merged
    }

    // MARK: Exercises

    /// Library movements are identified by name, not id: two devices seeding the
    /// same library produce different ids for the same exercise.
    private static func mergeExercises(in context: ModelContext) -> Int {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let groups = Dictionary(grouping: exercises) { $0.name.lowercased() }
        let duplicated = groups.filter { $0.value.count > 1 }
        guard !duplicated.isEmpty else { return 0 }

        // Repointing needs every referrer, and there are only two kinds.
        let blocks = (try? context.fetch(FetchDescriptor<ExerciseBlock>())) ?? []
        let items = (try? context.fetch(FetchDescriptor<RoutineItem>())) ?? []
        var merged = 0

        for (_, copies) in duplicated {
            guard let survivor = oldest(copies) else { continue }
            let losers = copies.filter { $0.id != survivor.id }
            let loserIDs = Set(losers.map(\.id))

            for block in blocks where block.exercise.map({ loserIDs.contains($0.id) }) == true {
                block.exercise = survivor
            }
            for item in items where item.exercise.map({ loserIDs.contains($0.id) }) == true {
                item.exercise = survivor
            }

            // Keep the more useful version of the flags rather than the survivor's
            // by accident: a movement hidden on one device stays hidden, and a
            // custom one stays custom.
            survivor.isCustom = survivor.isCustom || losers.contains(where: \.isCustom)
            survivor.isArchived = survivor.isArchived && losers.allSatisfy(\.isArchived)
            if survivor.notes.isEmpty, let notes = losers.first(where: { !$0.notes.isEmpty })?.notes {
                survivor.notes = notes
            }

            for loser in losers {
                context.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    // MARK: Athletes

    private static func mergeAthletes(in context: ModelContext) -> Int {
        let athletes = (try? context.fetch(FetchDescriptor<Athlete>())) ?? []
        let groups = Dictionary(grouping: athletes) { $0.name.lowercased() }
        let duplicated = groups.filter { $0.value.count > 1 }
        guard !duplicated.isEmpty else { return 0 }

        var merged = 0
        for (_, copies) in duplicated {
            guard let survivor = oldest(copies) else { continue }
            for loser in copies where loser.id != survivor.id {
                // Move the history across before deleting, or the cascade rule
                // takes the sessions with it.
                for session in loser.allSessions { session.athlete = survivor }
                for milestone in loser.allMilestones { milestone.athlete = survivor }
                for routine in loser.allRoutines { routine.athlete = survivor }
                for entry in loser.allBodyEntries { entry.athlete = survivor }
                if survivor.bodyweightKg == nil { survivor.bodyweightKg = loser.bodyweightKg }
                context.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    // MARK: Everything else

    /// Same id twice means the same record arrived twice. Keep one.
    private static func sweepDuplicateIDs(in context: ModelContext) -> Int {
        var merged = 0
        merged += sweep(WorkoutSession.self, id: \.id, in: context)
        merged += sweep(ExerciseBlock.self, id: \.id, in: context)
        merged += sweep(SetRecord.self, id: \.id, in: context)
        merged += sweep(Milestone.self, id: \.id, in: context)
        merged += sweep(Routine.self, id: \.id, in: context)
        merged += sweep(RoutineItem.self, id: \.id, in: context)
        merged += sweep(BodyEntry.self, id: \.id, in: context)
        return merged
    }

    private static func sweep<Model: PersistentModel>(
        _ type: Model.Type,
        id: KeyPath<Model, UUID>,
        in context: ModelContext
    ) -> Int {
        let all = (try? context.fetch(FetchDescriptor<Model>())) ?? []
        let groups = Dictionary(grouping: all) { $0[keyPath: id] }
        var merged = 0
        for (_, copies) in groups where copies.count > 1 {
            for loser in copies.dropFirst() {
                context.delete(loser)
                merged += 1
            }
        }
        return merged
    }

    /// Stable choice of survivor: oldest first, id as a tiebreak so both devices
    /// independently pick the same one.
    private static func oldest(_ exercises: [Exercise]) -> Exercise? {
        exercises.min {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
    }

    private static func oldest(_ athletes: [Athlete]) -> Athlete? {
        athletes.min {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
    }
}
