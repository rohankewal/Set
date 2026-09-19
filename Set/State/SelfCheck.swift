#if DEBUG
import SwiftData
import SwiftUI

/// A standing check of the rules that are easy to break and awkward to test by
/// hand: when a tick starts a rest, and what happens to records when a logged
/// set is corrected or un-ticked. Runs against the real engine in a throwaway
/// workout, which it discards afterwards.
///
/// `--screen selftest`. DEBUG only, so it never ships.
@MainActor
enum SelfCheck {
    static func run(context: ModelContext, settings: AppSettings) -> [String] {
        var out: [String] = []
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            out.append("\(passed ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }

        let athlete = Athlete(name: "Check")
        context.insert(athlete)
        let exercise = Exercise(name: "Check Lift \(UUID().uuidString.prefix(4))", muscle: .legs, equipment: .barbell)
        context.insert(exercise)
        let engine = WorkoutEngine(context: context, settings: settings)
        engine.start(for: athlete)
        guard let block = engine.addExercise(exercise) else { return ["FAIL  could not add exercise"] }

        let one = block.orderedSets[0]
        one.weightKg = 100; one.reps = 5
        let two = engine.addSet(to: block)
        two.weightKg = 100; two.reps = 5

        // 1. A normal tick starts the rest.
        engine.toggleCompletion(of: two, in: block)
        check("ticking a set starts rest", engine.isRestActive)
        let firstEnd = engine.restEndsAt

        // 2. Ticking an earlier set afterwards is catching up: rest untouched.
        engine.toggleCompletion(of: one, in: block)
        check("catching up on an earlier set doesn't restart rest", engine.restEndsAt == firstEnd)

        // 3. A run of quick ticks keeps one rest.
        let three = engine.addSet(to: block); three.weightKg = 100; three.reps = 5
        engine.toggleCompletion(of: three, in: block)
        check("a tick moments later keeps the running rest", engine.restEndsAt == firstEnd)

        // 4. After the rest ends, the next tick starts a fresh one.
        engine.endRest()
        let four = engine.addSet(to: block); four.weightKg = 100; four.reps = 5
        engine.toggleCompletion(of: four, in: block)
        check("a later set starts a new rest", engine.isRestActive && engine.restEndsAt != firstEnd)

        // 5. A set that sets a record, then corrected down: the record it
        // wrote is withdrawn and replaced by the corrected one, while records
        // earned by other sets stay.
        let baseline = athlete.allMilestones.filter { $0.kind == .estimatedMax }.map(\.value).max() ?? 0
        let big = engine.addSet(to: block); big.weightKg = 200; big.reps = 5
        engine.toggleCompletion(of: big, in: block)
        let recordFromBig = big.estimatedOneRepMaxKg
        check("a record set writes a new record",
              (athlete.allMilestones.filter { $0.kind == .estimatedMax }.map(\.value).max() ?? 0) > baseline)

        big.reps = 2
        engine.setDidChange(big, in: block)
        let values = athlete.allMilestones.filter { $0.kind == .estimatedMax }.map(\.value)
        check("set stays logged after a correction", big.isComplete)
        check("the withdrawn record is gone", !values.contains { abs($0 - recordFromBig) < 0.01 },
              "values \(values.map { Format.number($0) })")
        check("the record now matches the corrected set",
              abs((values.max() ?? 0) - big.estimatedOneRepMaxKg) < 0.01,
              "record \(Format.number(values.max() ?? 0)) vs set \(Format.number(big.estimatedOneRepMaxKg))")
        check("an earlier set's record survives", values.contains { abs($0 - baseline) < 0.01 })

        // 6. Un-ticking takes the records back with it.
        let stamp = big.completedAt
        engine.toggleCompletion(of: big, in: block)
        check("un-ticking withdraws its records",
              athlete.allMilestones.filter { $0.exerciseName == block.name && $0.achievedAt == stamp }.isEmpty)

        engine.discard()
        context.delete(athlete)
        context.delete(exercise)
        return out
    }
}

struct SelfCheckView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @State private var lines: [String] = []

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Self-check").font(.system(size: 24, weight: .semibold))
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("PASS") ? Ink.secondary : Ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Metric.gutter)
            }
        }
        .task { lines = SelfCheck.run(context: context, settings: settings) }
    }
}
#endif
