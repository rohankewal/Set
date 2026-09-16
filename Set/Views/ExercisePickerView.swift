import SwiftData
import SwiftUI

/// Search-first picker. Typing filters; if nothing matches, the first row
/// becomes "Create" so a missing movement never blocks a set.
struct ExercisePickerView: View {
    let onSelect: (Exercise) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Exercise> { !$0.isArchived }, sort: \Exercise.name)
    private var exercises: [Exercise]

    @State private var search = ""
    @State private var muscle: MuscleGroup?

    private var filtered: [Exercise] {
        exercises.filter { exercise in
            let matchesMuscle = muscle == nil || exercise.muscle == muscle
            let matchesSearch = search.isEmpty
                || exercise.name.localizedCaseInsensitiveContains(search)
            return matchesMuscle && matchesSearch
        }
    }

    private var grouped: [(MuscleGroup, [Exercise])] {
        Dictionary(grouping: filtered, by: \.muscle)
            .sorted { $0.key.label < $1.key.label }
            .map { ($0.key, $0.value) }
    }

    private var canCreate: Bool {
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 1 else { return false }
        return !exercises.contains { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        filterRow

                        if canCreate {
                            Button {
                                create(named: search.trimmingCharacters(in: .whitespaces))
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus")
                                    Text("Create “\(search.trimmingCharacters(in: .whitespaces))”")
                                    Spacer()
                                }
                            }
                            .buttonStyle(InkButtonStyle(prominent: false, height: 48))
                            .padding(.horizontal, Metric.gutter)
                        }

                        ForEach(grouped, id: \.0) { group, items in
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(group.label)
                                    .padding(.horizontal, Metric.gutter)
                                Card(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(items.enumerated()), id: \.element.id) { index, exercise in
                                            if index > 0 { Hairline(inset: 18) }
                                            Button {
                                                onSelect(exercise)
                                                dismiss()
                                            } label: {
                                                ExerciseRow(exercise: exercise)
                                                    .padding(.horizontal, 18)
                                                    .padding(.vertical, 12)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, Metric.gutter)
                            }
                        }

                        if filtered.isEmpty && !canCreate {
                            EmptyState(
                                symbol: "magnifyingglass",
                                title: "Nothing found",
                                message: "Try a different name or clear the filter."
                            )
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search movements")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button { muscle = nil } label: { Chip(text: "All", isSelected: muscle == nil) }
                    .buttonStyle(.plain)
                ForEach(MuscleGroup.allCases) { group in
                    Button { muscle = (muscle == group ? nil : group) } label: {
                        Chip(text: group.label, isSelected: muscle == group)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Metric.gutter)
        }
        .scrollIndicators(.hidden)
    }

    private func create(named name: String) {
        let exercise = Exercise(
            name: name,
            muscle: muscle ?? .fullBody,
            equipment: .other,
            isCustom: true
        )
        context.insert(exercise)
        context.saveChanges()
        onSelect(exercise)
        dismiss()
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.rowTitle)
                    .foregroundStyle(Ink.primary)
                Text(exercise.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.tertiary)
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.rowValue)
                    .foregroundStyle(Ink.secondary)
            }
        }
        .contentShape(.rect)
    }
}
