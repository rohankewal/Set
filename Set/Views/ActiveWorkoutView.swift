import SwiftData
import SwiftUI

struct ActiveWorkoutView: View {
    let athlete: Athlete?

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var showingPicker = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var award: MilestoneAward?

    private var session: WorkoutSession? { engine.session }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .medium))
        }
        // iOS 27: stays reachable even as the toolbar collapses on scroll.
        ToolbarItem(placement: .topBarPinnedTrailing) {
            Button("Finish") { confirmFinish = true }
                .font(.system(size: 15, weight: .semibold))
                .disabled(session?.completedSets.isEmpty ?? true)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingFocus = true
            } label: {
                Image(systemName: "viewfinder")
            }
            .accessibilityLabel("Focus mode")
            .disabled(session?.allBlocks.isEmpty ?? true)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Focus mode", systemImage: "viewfinder") { showingFocus = true }
                Button("Rename session", systemImage: "pencil") { renaming = true }
                Button("Session notes", systemImage: "text.alignleft") { editingNotes = true }
                Button("Save as routine", systemImage: "square.stack") { savingRoutine = true }
                Button("Discard workout", systemImage: "trash", role: .destructive) {
                    confirmDiscard = true
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
        // iOS 27: first item to collapse when the bar runs out of room.
        .visibilityPriority(.low)
    }

    var body: some View {
        NavigationStack {
            Screen {
                if let session {
                    content(for: session)
                } else {
                    EmptyState(
                        symbol: "checkmark.circle",
                        title: "Workout saved",
                        message: "Nothing is in progress."
                    )
                }
            }
            .navigationTitle(session?.title ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showingFocus) {
            if let session {
                FocusModeView(session: session, athlete: athlete)
            }
        }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                engine.addExercise(exercise)
            }
        }
        .sheet(isPresented: $editingNotes) {
            if let session {
                NoteEditor(title: "Session notes", text: Binding(
                    get: { session.notes },
                    set: { session.notes = $0 }
                ))
            }
        }
        .alert("Save as routine", isPresented: $savingRoutine) {
            TextField("Routine name", text: $routineName)
            Button("Save") {
                if let session {
                    let name = routineName.trimmingCharacters(in: .whitespaces)
                    engine.saveAsRoutine(session, named: name.isEmpty ? session.title : name, for: athlete)
                }
                routineName = ""
            }
            Button("Cancel", role: .cancel) { routineName = "" }
        } message: {
            Text("Keeps the exercises, their order and the sets you logged as a reusable plan.")
        }
        .alert("Session name", isPresented: $renaming) {
            TextField("Name", text: Binding(
                get: { session?.title ?? "" },
                set: { session?.title = $0 }
            ))
            Button("Done") {}
        }
        .confirmationDialog("Finish this workout?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish and save") {
                engine.finish()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                engine.discard()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        }
        .overlay(alignment: .top) {
            if let award {
                AwardBanner(award: award, unit: settings.unit)
                    .padding(.horizontal, Metric.gutter)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: engine.pendingAwards.count) { await drainAwards() }
        .animation(Motion.snap, value: award?.id)
    }

    @State private var renaming = false
    @State private var editingNotes = false
    @State private var savingRoutine = false
    @State private var showingFocus = false
    @State private var routineName = ""

    // MARK: Body

    private func content(for session: WorkoutSession) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                summaryStrip(for: session)
                    .padding(.bottom, 4)

                // iOS 27 reordering: drag an exercise card anywhere in the stack.
                ForEach(session.orderedBlocks) { block in
                    ExerciseBlockCard(block: block, athlete: athlete)
                }
                .reorderable()

                Button {
                    showingPicker = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Add exercise")
                    }
                }
                .buttonStyle(InkButtonStyle(prominent: false, height: 50))
                .padding(.top, 6)

                if session.allBlocks.isEmpty {
                    EmptyState(
                        symbol: "dumbbell",
                        title: "Empty session",
                        message: "Add your first exercise. Weights and reps prefill from last time."
                    )
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .reorderContainer(for: ExerciseBlock.self) { difference in
            var blocks = session.orderedBlocks
            let moving = difference.sources.compactMap { id in blocks.first { $0.id == id } }
            blocks.removeAll { moving.contains($0) }
            switch difference.destination.position {
            case .before(let id):
                let index = blocks.firstIndex { $0.id == id } ?? blocks.count
                blocks.insert(contentsOf: moving, at: index)
            case .end:
                blocks.append(contentsOf: moving)
            }
            engine.reorder(blocks)
        }
    }

    private func summaryStrip(for session: WorkoutSession) -> some View {
        HStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                StatTile(
                    label: "Elapsed",
                    value: Format.clock(Date.now.timeIntervalSince(session.startedAt))
                )
            }
            StatTile(label: "Sets", value: "\(session.completedSets.count)")
            StatTile(
                label: "Volume",
                value: Format.volume(session.volumeKg, in: settings.unit),
                unit: settings.unit.short
            )
        }
        .padding(.top, 4)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        RestDock(exercise: currentExerciseName)
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 10)
    }

    /// The exercise a fresh rest belongs to — the last one touched, else the last
    /// one added, so the rest-complete alert can name it.
    private var currentExerciseName: String {
        guard let session else { return "" }
        let latest = session.allBlocks
            .flatMap(\.allSets)
            .filter(\.isComplete)
            .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        return latest?.block?.name ?? session.orderedBlocks.last?.name ?? ""
    }

    // MARK: Side effects

    private func drainAwards() async {
        while !engine.pendingAwards.isEmpty {
            guard let next = engine.consumeAward() else { break }
            award = next
            try? await Task.sleep(for: .seconds(2.6))
            award = nil
            try? await Task.sleep(for: .seconds(0.25))
        }
    }

}

// MARK: - Award banner

struct AwardBanner: View {
    let award: MilestoneAward
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: award.kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.onAccent)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(award.kind.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Ink.onAccent.opacity(0.7))
                Text(MilestoneFormatter.headline(for: award, unit: unit))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ink.onAccent)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Ink.accent, in: .rect(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

enum MilestoneFormatter {
    static func headline(for award: MilestoneAward, unit: WeightUnit) -> String {
        headline(kind: award.kind, exerciseName: award.exerciseName, value: award.value, unit: unit)
    }

    static func headline(for milestone: Milestone, unit: WeightUnit) -> String {
        headline(kind: milestone.kind, exerciseName: milestone.exerciseName, value: milestone.value, unit: unit)
    }

    static func headline(kind: MilestoneKind, exerciseName: String, value: Double, unit: WeightUnit) -> String {
        switch kind {
        case .heaviestSet, .estimatedMax:
            "\(exerciseName) · \(Format.weight(value, in: unit)) \(unit.short)"
        case .repRecord:
            "\(exerciseName) · \(Format.number(value, maxFractionDigits: 0)) reps"
        case .volumeRecord:
            "\(exerciseName) · \(Format.volume(value, in: unit)) \(unit.short)"
        case .sessionCount:
            "\(Format.number(value, maxFractionDigits: 0)) workouts logged"
        case .streak:
            "\(Format.number(value, maxFractionDigits: 0)) weeks in a row"
        case .lifetimeVolume:
            "\(Format.volume(value, in: unit)) \(unit.short) lifted all-time"
        }
    }
}
