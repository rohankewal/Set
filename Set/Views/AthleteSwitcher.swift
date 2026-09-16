import SwiftData
import SwiftUI

/// Solo users see one row and never come back. Coaches add a person per client
/// and switch here; everything else in the app follows the selection.
struct AthleteSwitcher: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Athlete.createdAt) private var athletes: [Athlete]
    @State private var newName = ""
    @State private var renaming: Athlete?

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(athletes.enumerated()), id: \.element.id) { index, athlete in
                                    if index > 0 { Hairline(inset: 18) }
                                    row(for: athlete)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Add someone")
                            HStack(spacing: 10) {
                                TextField("Name", text: $newName)
                                    .font(.system(size: 16, weight: .medium))
                                    .padding(.horizontal, 16)
                                    .frame(height: 48)
                                    .background(Ink.surface, in: .rect(cornerRadius: Metric.controlRadius, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Metric.controlRadius, style: .continuous)
                                            .strokeBorder(Ink.line, lineWidth: Metric.hairline)
                                    }
                                    .submitLabel(.done)
                                    .onSubmit(add)
                                Button {
                                    add()
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(IconButtonStyle(size: 48, filled: true))
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }

                        Text("Each person keeps their own history, records and milestones.")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.tertiary)
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Athletes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold))
                }
            }
            .alert("Rename", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: Binding(
                    get: { renaming?.name ?? "" },
                    set: { renaming?.rename($0) }
                ))
                Button("Done") {
                    if let athlete = renaming {
                        let trimmed = athlete.name.trimmingCharacters(in: .whitespaces)
                        athlete.rename(trimmed.isEmpty ? "Athlete" : trimmed)
                    }
                    context.saveChanges()
                    renaming = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(for athlete: Athlete) -> some View {
        let isSelected = athlete.id == settings.selectedAthleteID

        return Button {
            guard !engine.isRunning else { return }
            settings.selectedAthleteID = athlete.id
            Haptics.play(.tick)
            dismiss()
        } label: {
            HStack(spacing: 13) {
                Text(athlete.initials)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Ink.onAccent : Ink.primary)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? Ink.accent : Ink.surfaceHigh, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(athlete.name)
                        .font(.rowTitle)
                        .foregroundStyle(Ink.primary)
                    Text("\(athlete.completedSessions.count) session\(athlete.completedSessions.count == 1 ? "" : "s")")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Ink.tertiary)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Ink.primary)
                }
                // Renaming is the most common reason to open this sheet at all,
                // so it gets a real target rather than hiding in a long press.
                Button { renaming = athlete } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 30, height: 30)
                        .background(Ink.surfaceHigh, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rename \(athlete.name)")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename", systemImage: "pencil") { renaming = athlete }
            if athletes.count > 1 {
                Button("Delete person and history", systemImage: "trash", role: .destructive) {
                    if settings.selectedAthleteID == athlete.id {
                        settings.selectedAthleteID = athletes.first { $0.id != athlete.id }?.id
                    }
                    context.delete(athlete)
                    context.saveChanges()
                }
            }
        }
        .disabled(engine.isRunning && !isSelected)
    }

    private func add() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let athlete = Athlete(name: trimmed)
        context.insert(athlete)
        context.saveChanges()
        settings.selectedAthleteID = athlete.id
        newName = ""
        Haptics.play(.complete)
    }
}
