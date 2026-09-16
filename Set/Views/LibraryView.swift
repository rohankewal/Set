import SwiftData
import SwiftUI

/// The movement library: browse, create, tidy up. Read-mostly, so it stays a
/// plain list with a single search field.
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var search = ""
    @State private var creating = false

    private var filtered: [Exercise] {
        search.isEmpty
            ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var grouped: [(MuscleGroup, [Exercise])] {
        Dictionary(grouping: filtered, by: \.muscle)
            .sorted { $0.key.label < $1.key.label }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(grouped, id: \.0) { group, items in
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: group.label) {
                                    Text("\(items.count)")
                                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Ink.secondary)
                                }
                                Card(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { index, exercise in
                                            if index > 0 { Hairline(inset: 18) }
                                            ExerciseLibraryRow(exercise: exercise)
                                        }
                                    }
                                }
                            }
                        }

                        if filtered.isEmpty {
                            EmptyState(
                                symbol: "square.grid.2x2",
                                title: "No movements",
                                message: "Create one and it will be available in every workout."
                            )
                        }
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Search movements")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New exercise")
                }
            }
            .sheet(isPresented: $creating) { ExerciseEditor() }
        }
    }
}

private struct ExerciseLibraryRow: View {
    @Bindable var exercise: Exercise
    @Environment(\.modelContext) private var context
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            ExerciseRow(
                exercise: exercise,
                trailing: exercise.isCustom ? "Custom" : nil
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editing = true }
            Button("Hide from library", systemImage: "eye.slash", role: .destructive) {
                exercise.isArchived = true
                context.saveChanges()
            }
        }
        .sheet(isPresented: $editing) { ExerciseEditor(exercise: exercise) }
    }
}

/// Create or edit one movement. Four fields, nothing more.
struct ExerciseEditor: View {
    var exercise: Exercise?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var muscle: MuscleGroup = .fullBody
    @State private var equipment: Equipment = .barbell
    @State private var tracking: TrackingStyle = .weightAndReps

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Name")
                            TextField("Movement name", text: $name)
                                .font(.system(size: 17, weight: .medium))
                                .padding(.horizontal, 16)
                                .frame(height: 50)
                                .background(Ink.surface, in: .rect(cornerRadius: Metric.controlRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Metric.controlRadius, style: .continuous)
                                        .strokeBorder(Ink.line, lineWidth: Metric.hairline)
                                }
                        }

                        pickerGroup("Muscle", selection: $muscle, values: MuscleGroup.allCases) { $0.label }
                        pickerGroup("Equipment", selection: $equipment, values: Equipment.allCases) { $0.label }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Measured in")
                            Picker("Measured in", selection: $tracking) {
                                Text("Weight × reps").tag(TrackingStyle.weightAndReps)
                                Text("Reps").tag(TrackingStyle.repsOnly)
                                Text("Time").tag(TrackingStyle.duration)
                            }
                            .pickerStyle(.segmented)
                        }

                        Button(exercise == nil ? "Create movement" : "Save changes") { save() }
                            .buttonStyle(InkButtonStyle())
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(exercise == nil ? "New movement" : "Edit movement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                guard let exercise else { return }
                name = exercise.name
                muscle = exercise.muscle
                equipment = exercise.equipment
                tracking = exercise.tracking
            }
        }
        .presentationDetents([.large])
    }

    private func pickerGroup<T: Hashable & Identifiable>(
        _ title: String,
        selection: Binding<T>,
        values: [T],
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(values) { value in
                        Button { selection.wrappedValue = value } label: {
                            Chip(text: label(value), isSelected: selection.wrappedValue == value)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let exercise {
            exercise.name = trimmed
            exercise.muscle = muscle
            exercise.equipment = equipment
            exercise.tracking = tracking
        } else {
            context.insert(
                Exercise(name: trimmed, muscle: muscle, equipment: equipment, tracking: tracking, isCustom: true)
            )
        }
        context.saveChanges()
        dismiss()
    }
}
