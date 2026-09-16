import SwiftData
import SwiftUI

/// Saved plans. Most get made by finishing a workout and tapping "Save as
/// routine" — building one by hand is the fallback, not the main path, which is
/// the opposite of how template builders usually work.
struct RoutinesView: View {
    let athlete: Athlete?
    let onStart: (Routine) -> Void

    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Routine?
    @State private var creating = false

    private var routines: [Routine] {
        (athlete?.allRoutines ?? []).sorted {
            ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if routines.isEmpty {
                            EmptyState(
                                symbol: "square.stack",
                                title: "No routines yet",
                                message: "Finish a workout and save it as a routine, or build one here."
                            )
                        }

                        ForEach(routines) { routine in
                            RoutineCard(
                                routine: routine,
                                start: {
                                    onStart(routine)
                                    dismiss()
                                },
                                edit: { editing = routine }
                            )
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = routine }
                                Button("Duplicate", systemImage: "plus.square.on.square") {
                                    duplicate(routine)
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    context.delete(routine)
                                    context.saveChanges()
                                }
                            }
                        }

                        Button {
                            creating = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("New routine")
                            }
                        }
                        .buttonStyle(InkButtonStyle(prominent: false, height: 50))
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Routines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold))
                }
            }
            .sheet(item: $editing) { routine in
                RoutineEditor(routine: routine, athlete: athlete)
            }
            .sheet(isPresented: $creating) {
                RoutineEditor(routine: nil, athlete: athlete)
            }
        }
    }

    private func duplicate(_ routine: Routine) {
        let copy = Routine(name: routine.name + " copy", athlete: athlete, notes: routine.notes)
        context.insert(copy)
        for item in routine.orderedItems {
            let new = RoutineItem(
                exercise: item.exercise,
                order: item.order,
                targetSets: item.targetSets,
                targetReps: item.targetReps,
                targetWeightKg: item.targetWeightKg,
                restSeconds: item.restSeconds,
                supersetGroup: item.supersetGroup
            )
            new.routine = copy
            context.insert(new)
        }
        context.saveChanges()
    }
}

struct RoutineCard: View {
    let routine: Routine
    let start: () -> Void
    let edit: () -> Void

    @Environment(WorkoutEngine.self) private var engine

    private var metadata: String {
        var parts = ["^[\(routine.orderedItems.count) exercise](inflect: true)", "\(routine.totalSets) sets"]
        if routine.useCount > 0 { parts.append("used \(routine.useCount)×") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(routine.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Ink.primary)
                        Text(routine.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.tertiary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button(action: edit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 30, height: 30)
                            .background(Ink.surfaceHigh, in: .circle)
                    }
                    .buttonStyle(.plain)
                }

                Text(metadata)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)

                Button("Start", action: start)
                    .buttonStyle(InkButtonStyle(height: 46))
                    .disabled(engine.isRunning || routine.allItems.isEmpty)
            }
        }
    }
}

// MARK: - Editor

struct RoutineEditor: View {
    var routine: Routine?
    let athlete: Athlete?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    @State private var name = ""
    @State private var draft: Routine?
    @State private var addingExercise = false

    private var items: [RoutineItem] { draft?.orderedItems ?? [] }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Name")
                            TextField("Routine name", text: $name)
                                .font(.system(size: 17, weight: .medium))
                                .padding(.horizontal, 16)
                                .frame(height: 50)
                                .background(Ink.surface, in: .rect(cornerRadius: Metric.controlRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Metric.controlRadius, style: .continuous)
                                        .strokeBorder(Ink.line, lineWidth: Metric.hairline)
                                }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Exercises") {
                                Text("\(items.count)")
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Ink.secondary)
                            }

                            if items.isEmpty {
                                Card {
                                    Text("Add the movements you want, with a target of sets and reps. Weights fill in from your history when you start it.")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Ink.tertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                ForEach(items) { item in
                                    RoutineItemRow(item: item) {
                                        context.delete(item)
                                        reindex()
                                    }
                                }
                            }
                        }

                        Button {
                            addingExercise = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("Add exercise")
                            }
                        }
                        .buttonStyle(InkButtonStyle(prominent: false, height: 50))
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(routine == nil ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.system(size: 15, weight: .semibold))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $addingExercise) {
                ExercisePickerView { exercise in
                    add(exercise)
                }
            }
            .onAppear(perform: prepare)
        }
        .presentationDetents([.large])
    }

    /// New routines are inserted immediately so items have somewhere to live;
    /// cancelling deletes the draft rather than leaving an orphan.
    private func prepare() {
        guard draft == nil else { return }
        if let routine {
            draft = routine
            name = routine.name
        } else {
            let new = Routine(name: "", athlete: athlete)
            context.insert(new)
            draft = new
        }
    }

    private func add(_ exercise: Exercise) {
        guard let draft else { return }
        let item = RoutineItem(
            exercise: exercise,
            order: (draft.allItems.map(\.order).max() ?? -1) + 1,
            targetSets: 3,
            targetReps: exercise.tracking == .duration ? 30 : 8,
            restSeconds: settings.defaultRestSeconds
        )
        item.routine = draft
        context.insert(item)
    }

    private func reindex() {
        for (offset, item) in items.enumerated() { item.order = offset }
    }

    private func save() {
        draft?.name = name.trimmingCharacters(in: .whitespaces)
        reindex()
        context.saveChanges()
        Haptics.play(.complete)
        dismiss()
    }

    private func cancel() {
        if routine == nil, let draft {
            context.delete(draft)
            context.saveChanges()
        }
        dismiss()
    }
}

private struct RoutineItemRow: View {
    @Bindable var item: RoutineItem
    let delete: () -> Void

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(item.name)
                        .font(.rowTitle)
                        .foregroundStyle(Ink.primary)
                    Spacer()
                    Button(action: delete) {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 26, height: 26)
                            .background(Ink.surfaceHigh, in: .circle)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    counter(label: "Sets", value: $item.targetSets, range: 1...12)
                    counter(
                        label: item.exercise?.tracking == .duration ? "Seconds" : "Reps",
                        value: $item.targetReps,
                        range: 1...300,
                        step: item.exercise?.tracking == .duration ? 5 : 1
                    )
                }
            }
        }
    }

    private func counter(label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack(spacing: 8) {
            Text(label).microLabelStyle()
            Spacer(minLength: 0)
            Button {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                Haptics.play(.tick)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            Text("\(value.wrappedValue)")
                .font(.readout(17, weight: .medium))
                .foregroundStyle(Ink.primary)
                .frame(width: 34)
                .contentTransition(.numericText())
            Button {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                Haptics.play(.tick)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(IconButtonStyle(size: 28))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Ink.surfaceHigh.opacity(0.5), in: .rect(cornerRadius: Metric.controlRadius, style: .continuous))
    }
}
