import Foundation
import SwiftData

/// The schema, versioned.
///
/// SwiftData can infer simple migrations (adding a property, adding a model) and
/// it does — that's how the routines and body-weight release opened existing
/// stores. What it can't infer is a rename, a type change, or a split, and when
/// inference fails the store won't open at all. Declaring versions now means
/// those changes get an explicit stage later instead of an unopenable store.
enum SetSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Athlete.self,
            Exercise.self,
            WorkoutSession.self,
            ExerciseBlock.self,
            SetRecord.self,
            Milestone.self,
            Routine.self,
            RoutineItem.self,
            BodyEntry.self
        ]
    }
}

enum SetMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SetSchemaV1.self]
    }

    /// Empty until a change needs one. Each future version adds a stage here —
    /// `.lightweight` where inference copes, `.custom` where it doesn't.
    static var stages: [MigrationStage] {
        []
    }
}
