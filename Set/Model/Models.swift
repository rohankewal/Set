import Foundation
import SwiftData

// MARK: - Athlete
//
// "Set" is built so one person can track themselves, or a coach can track a
// handful of people. There is always exactly one selected athlete; a solo user
// never has to think about the concept.

@Model
final class Athlete {

    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now
    /// Monogram shown in the switcher. Derived on write so it stays cheap to read.
    var initials: String = ""
    var bodyweightKg: Double?

    // CloudKit requires every to-many relationship to be optional. The stored
    // properties follow that rule; the `all…` accessors keep the rest of the
    // app free of `?? []`.
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSession.athlete)
    var sessions: [WorkoutSession]?
    var allSessions: [WorkoutSession] { sessions ?? [] }

    @Relationship(deleteRule: .cascade, inverse: \Milestone.athlete)
    var milestones: [Milestone]?
    var allMilestones: [Milestone] { milestones ?? [] }

    @Relationship(deleteRule: .cascade, inverse: \Routine.athlete)
    var routines: [Routine]?
    var allRoutines: [Routine] { routines ?? [] }

    @Relationship(deleteRule: .cascade, inverse: \BodyEntry.athlete)
    var bodyEntries: [BodyEntry]?
    var allBodyEntries: [BodyEntry] { bodyEntries ?? [] }

    init(name: String, bodyweightKg: Double? = nil) {
        self.id = UUID()
        self.name = name
        self.initials = Athlete.monogram(for: name)
        self.bodyweightKg = bodyweightKg
        self.createdAt = .now
    }

    func rename(_ newName: String) {
        name = newName
        initials = Athlete.monogram(for: newName)
    }

    static func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "—" : letters.joined().uppercased()
    }

    var completedSessions: [WorkoutSession] {
        allSessions.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }
}

// MARK: - Exercise

enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, back, shoulders, arms, legs, glutes, core, fullBody, cardio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fullBody: "Full body"
        default: rawValue.capitalized
        }
    }
}

enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell
    case smith, band, sled, ball, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smith: "Smith machine"
        case .ball: "Med ball"
        case .band: "Band"
        case .sled: "Sled"
        default: rawValue.capitalized
        }
    }
}

/// How a movement is measured. Drives the keypad and the PR maths.
enum TrackingStyle: String, Codable, CaseIterable, Sendable {
    /// Weight × reps (the default).
    case weightAndReps
    /// Reps only — push-ups, pull-ups.
    case repsOnly
    /// Seconds — planks, hangs.
    case duration

    var usesWeight: Bool { self == .weightAndReps }
    var usesReps: Bool { self != .duration }
}

@Model
final class Exercise {
    #Index<Exercise>([\.name])

    var id: UUID = UUID()
    var name: String = ""
    var muscleRaw: String = MuscleGroup.fullBody.rawValue
    var equipmentRaw: String = Equipment.other.rawValue
    var trackingRaw: String = TrackingStyle.weightAndReps.rawValue
    var isCustom: Bool = false
    var isArchived: Bool = false
    var notes: String = ""
    var createdAt: Date = Date.now

    // CloudKit requires an inverse for every relationship. Nothing reads these
    // directly — they exist so `ExerciseBlock.exercise` and
    // `RoutineItem.exercise` are valid, and nullify so deleting a movement can
    // never take logged history with it.
    @Relationship(deleteRule: .nullify, inverse: \ExerciseBlock.exercise)
    var blocks: [ExerciseBlock]?

    @Relationship(deleteRule: .nullify, inverse: \RoutineItem.exercise)
    var routineItems: [RoutineItem]?

    init(
        name: String,
        muscle: MuscleGroup,
        equipment: Equipment,
        tracking: TrackingStyle = .weightAndReps,
        isCustom: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.muscleRaw = muscle.rawValue
        self.equipmentRaw = equipment.rawValue
        self.trackingRaw = tracking.rawValue
        self.isCustom = isCustom
        self.createdAt = .now
    }

    var muscle: MuscleGroup {
        get { MuscleGroup(rawValue: muscleRaw) ?? .fullBody }
        set { muscleRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var tracking: TrackingStyle {
        get { TrackingStyle(rawValue: trackingRaw) ?? .weightAndReps }
        set { trackingRaw = newValue.rawValue }
    }

    var subtitle: String { "\(equipment.label) · \(muscle.label)" }
}

// MARK: - Session

@Model
final class WorkoutSession {
    #Index<WorkoutSession>([\.startedAt])

    var id: UUID = UUID()
    var title: String = "Workout"
    var startedAt: Date = Date.now
    var endedAt: Date?
    var notes: String = ""
    var athlete: Athlete?

    @Relationship(deleteRule: .cascade, inverse: \ExerciseBlock.session)
    var blocks: [ExerciseBlock]?
    var allBlocks: [ExerciseBlock] { blocks ?? [] }

    init(title: String = "Workout", athlete: Athlete?, startedAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.athlete = athlete
        self.startedAt = startedAt
    }

    var isActive: Bool { endedAt == nil }

    var orderedBlocks: [ExerciseBlock] {
        allBlocks.sorted { $0.order < $1.order }
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }

    var completedSets: [SetRecord] {
        allBlocks.flatMap(\.allSets).filter(\.isComplete)
    }

    var workingSets: [SetRecord] {
        completedSets.filter { $0.kind.countsTowardVolume }
    }

    /// Total tonnage in kilograms across completed working sets.
    var volumeKg: Double {
        workingSets.reduce(0) { $0 + $1.volumeKg }
    }

    var totalReps: Int {
        workingSets.reduce(0) { $0 + $1.reps }
    }
}

// MARK: - Block (one exercise inside a session)

@Model
final class ExerciseBlock {

    var id: UUID = UUID()
    var order: Int = 0
    var restSeconds: Int = 90
    var notes: String = ""
    /// Exercises sharing a group number are a superset: they're performed
    /// back-to-back and only the last one in the group triggers a rest.
    var supersetGroup: Int?
    var session: WorkoutSession?
    var exercise: Exercise?

    @Relationship(deleteRule: .cascade, inverse: \SetRecord.block)
    var sets: [SetRecord]?
    var allSets: [SetRecord] { sets ?? [] }

    init(exercise: Exercise?, order: Int, restSeconds: Int = 90) {
        self.id = UUID()
        self.exercise = exercise
        self.order = order
        self.restSeconds = restSeconds
    }

    var orderedSets: [SetRecord] {
        allSets.sorted { $0.index < $1.index }
    }

    var name: String { exercise?.name ?? "Exercise" }
    var tracking: TrackingStyle { exercise?.tracking ?? .weightAndReps }
    /// Whether the load sits on a bar — decides if the plate calculator and the
    /// empty-bar floor apply.
    var equipmentUsesBar: Bool {
        switch exercise?.equipment {
        case .barbell, .smith: true
        default: false
        }
    }

    var isFinished: Bool {
        !allSets.isEmpty && allSets.allSatisfy(\.isComplete)
    }

    var completedCount: Int { allSets.count(where: \.isComplete) }

    var volumeKg: Double {
        allSets.filter { $0.isComplete && $0.kind.countsTowardVolume }.reduce(0) { $0 + $1.volumeKg }
    }

    /// Superset partners, ordered, including this block.
    func supersetPeers(in session: WorkoutSession?) -> [ExerciseBlock] {
        guard let group = supersetGroup, let session else { return [self] }
        return session.orderedBlocks.filter { $0.supersetGroup == group }
    }

    /// Rest only fires after the last exercise in a superset.
    func isLastInSuperset(of session: WorkoutSession?) -> Bool {
        guard supersetGroup != nil else { return true }
        return supersetPeers(in: session).last?.id == id
    }
}

// MARK: - Set

/// How a set counts. Warm-ups are excluded from volume and records; drop sets
/// count toward volume but never toward a heaviest-set record; AMRAP sets are
/// where rep records come from.
enum SetKind: String, Codable, CaseIterable, Sendable {
    case working, warmup, drop, failure, amrap

    var label: String {
        switch self {
        case .working: "Working set"
        case .warmup: "Warm-up"
        case .drop: "Drop set"
        case .failure: "To failure"
        case .amrap: "AMRAP"
        }
    }

    /// Single character shown in the set-number column.
    var badge: String {
        switch self {
        case .working: ""
        case .warmup: "W"
        case .drop: "D"
        case .failure: "F"
        case .amrap: "A"
        }
    }

    /// Warm-ups are bookkeeping, not training volume.
    var countsTowardVolume: Bool { self != .warmup }
    /// A drop set is by definition lighter than the set it followed.
    var countsTowardLoadRecords: Bool { self == .working || self == .failure || self == .amrap }
}

@Model
final class SetRecord {

    var id: UUID = UUID()
    var index: Int = 0
    var weightKg: Double = 0
    var reps: Int = 0
    /// Seconds, for duration-tracked movements.
    var seconds: Int = 0
    /// Retained as the stored flag it always was; `kind` is the source of truth
    /// and keeps this in sync so older records keep behaving.
    var isWarmup: Bool = false
    var kindRaw: String = SetKind.working.rawValue
    var isComplete: Bool = false
    var completedAt: Date?
    /// Rate of perceived exertion, 6–10. Optional by design; nobody is forced to log it.
    var rpe: Double?
    var block: ExerciseBlock?

    init(
        index: Int,
        weightKg: Double = 0,
        reps: Int = 0,
        seconds: Int = 0,
        kind: SetKind = .working
    ) {
        self.id = UUID()
        self.index = index
        self.weightKg = weightKg
        self.reps = reps
        self.seconds = seconds
        self.kindRaw = kind.rawValue
        self.isWarmup = kind == .warmup
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? (isWarmup ? .warmup : .working) }
        set {
            kindRaw = newValue.rawValue
            isWarmup = newValue == .warmup
        }
    }

    var volumeKg: Double { weightKg * Double(reps) }

    /// Epley one-rep-max estimate. Only meaningful for loaded sets.
    var estimatedOneRepMaxKg: Double {
        guard weightKg > 0, reps > 0 else { return 0 }
        guard reps > 1 else { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}

// MARK: - Milestone

enum MilestoneKind: String, Codable, CaseIterable, Sendable {
    case heaviestSet
    case estimatedMax
    case repRecord
    case volumeRecord
    case sessionCount
    case streak
    case lifetimeVolume

    var label: String {
        switch self {
        case .heaviestSet: "Heaviest set"
        case .estimatedMax: "Estimated max"
        case .repRecord: "Rep record"
        case .volumeRecord: "Session volume"
        case .sessionCount: "Sessions logged"
        case .streak: "Week streak"
        case .lifetimeVolume: "Lifetime volume"
        }
    }

    var symbol: String {
        switch self {
        case .heaviestSet: "arrow.up.circle"
        case .estimatedMax: "chart.line.uptrend.xyaxis"
        case .repRecord: "repeat"
        case .volumeRecord: "square.stack.3d.up"
        case .sessionCount: "checkmark.seal"
        case .streak: "flame"
        case .lifetimeVolume: "mountain.2"
        }
    }

    /// Per-exercise records are namespaced by exercise; account-level ones are not.
    var isExerciseScoped: Bool {
        switch self {
        case .heaviestSet, .estimatedMax, .repRecord, .volumeRecord: true
        case .sessionCount, .streak, .lifetimeVolume: false
        }
    }
}

@Model
final class Milestone {
    #Index<Milestone>([\.achievedAt])

    var id: UUID = UUID()
    var kindRaw: String = MilestoneKind.heaviestSet.rawValue
    var exerciseName: String = ""
    var value: Double = 0
    var previousValue: Double = 0
    var achievedAt: Date = Date.now
    var athlete: Athlete?

    init(
        kind: MilestoneKind,
        exerciseName: String = "",
        value: Double,
        previousValue: Double = 0,
        athlete: Athlete?,
        achievedAt: Date = .now
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.exerciseName = exerciseName
        self.value = value
        self.previousValue = previousValue
        self.athlete = athlete
        self.achievedAt = achievedAt
    }

    var kind: MilestoneKind {
        MilestoneKind(rawValue: kindRaw) ?? .heaviestSet
    }

    var headline: String {
        kind.isExerciseScoped ? exerciseName : kind.label
    }
}


// MARK: - Routines

/// A saved plan: the exercises, their order, and target sets/reps. Routines are
/// per-athlete, and can be built by hand or lifted straight off a workout you
/// just finished — which is how most of them get made.
@Model
final class Routine {

    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    var lastUsedAt: Date?
    var useCount: Int = 0
    var athlete: Athlete?

    @Relationship(deleteRule: .cascade, inverse: \RoutineItem.routine)
    var items: [RoutineItem]?
    var allItems: [RoutineItem] { items ?? [] }

    init(name: String, athlete: Athlete?, notes: String = "") {
        self.id = UUID()
        self.name = name
        self.athlete = athlete
        self.notes = notes
    }

    var orderedItems: [RoutineItem] {
        allItems.sorted { $0.order < $1.order }
    }

    var summary: String {
        let names = orderedItems.compactMap { $0.exercise?.name }
        guard !names.isEmpty else { return "No exercises yet" }
        return names.prefix(3).joined(separator: " · ") + (names.count > 3 ? " +\(names.count - 3)" : "")
    }

    var totalSets: Int {
        orderedItems.reduce(0) { $0 + $1.targetSets }
    }
}

@Model
final class RoutineItem {

    var id: UUID = UUID()
    var order: Int = 0
    var targetSets: Int = 3
    var targetReps: Int = 8
    var targetWeightKg: Double?
    var restSeconds: Int = 90
    var supersetGroup: Int?
    var routine: Routine?
    var exercise: Exercise?

    init(
        exercise: Exercise?,
        order: Int,
        targetSets: Int = 3,
        targetReps: Int = 8,
        targetWeightKg: Double? = nil,
        restSeconds: Int = 90,
        supersetGroup: Int? = nil
    ) {
        self.id = UUID()
        self.exercise = exercise
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
    }

    var name: String { exercise?.name ?? "Exercise" }
}

// MARK: - Body weight

/// One body-weight reading. Deliberately just weight — measurements and photos
/// are a different app, and this one is about what you lifted.
@Model
final class BodyEntry {
    #Index<BodyEntry>([\.date])

    var id: UUID = UUID()
    var date: Date = Date.now
    var weightKg: Double = 0
    var athlete: Athlete?

    init(date: Date = .now, weightKg: Double, athlete: Athlete?) {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
        self.athlete = athlete
    }
}
