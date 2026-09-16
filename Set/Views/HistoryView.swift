import SwiftData
import SwiftUI

struct HistoryView: View {
    let athlete: Athlete?
    @Environment(AppSettings.self) private var settings

    private var sessions: [WorkoutSession] { athlete?.completedSessions ?? [] }

    private var months: [(label: String, sessions: [WorkoutSession])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { session -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: session.startedAt)) ?? session.startedAt
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (label: $0.key.formatted(.dateTime.month(.wide).year()), sessions: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if sessions.isEmpty {
                            EmptyState(
                                symbol: "list.bullet.indent",
                                title: "No history yet",
                                message: "Finished workouts are listed here, newest first."
                            )
                        }

                        ForEach(months, id: \.label) { month in
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: month.label) {
                                    Text(Format.volume(month.sessions.reduce(0) { $0 + $1.volumeKg }, in: settings.unit) + " " + settings.unit.short)
                                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Ink.secondary)
                                }
                                Card(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(month.sessions.enumerated()), id: \.element.id) { index, session in
                                            if index > 0 { Hairline(inset: 18) }
                                            NavigationLink {
                                                SessionDetailView(session: session)
                                                    .navigationTransition(.crossFade)
                                            } label: {
                                                SessionRow(session: session)
                                                    .padding(.horizontal, 18)
                                                    .padding(.vertical, 14)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("History")
        }
    }
}

struct SessionRow: View {
    let session: WorkoutSession
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.rowTitle)
                    .foregroundStyle(Ink.primary)
                Text(caption)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Readout(
                    value: Format.volume(session.volumeKg, in: settings.unit),
                    unit: settings.unit.short,
                    size: 19
                )
                Text(Format.relativeDay(session.startedAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .contentShape(.rect)
    }

    private var caption: String {
        let exercises = session.orderedBlocks.count
        let sets = session.workingSets.count
        return "\(Format.shortDuration(session.duration)) · \(exercises) exercise\(exercises == 1 ? "" : "s") · \(sets) set\(sets == 1 ? "" : "s")"
    }
}

// MARK: - Detail

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 0) {
                        StatTile(label: "Duration", value: Format.shortDuration(session.duration))
                        StatTile(label: "Sets", value: "\(session.workingSets.count)")
                        StatTile(
                            label: "Volume",
                            value: Format.volume(session.volumeKg, in: settings.unit),
                            unit: settings.unit.short
                        )
                    }

                    ForEach(session.orderedBlocks) { block in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: block.name) {
                                Text(Format.volume(block.volumeKg, in: settings.unit) + " " + settings.unit.short)
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Ink.secondary)
                            }
                            Card(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(block.orderedSets.enumerated()), id: \.element.id) { index, set in
                                        if index > 0 { Hairline(inset: 18) }
                                        CompletedSetRow(set: set, tracking: block.tracking)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 11)
                                    }
                                }
                            }
                        }
                    }

                    if !session.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Notes")
                            Card {
                                Text(session.notes)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Ink.secondary)
                            }
                        }
                    }

                    Button("Repeat this workout") {
                        engine.repeatSession(session, for: session.athlete)
                        dismiss()
                    }
                    .buttonStyle(InkButtonStyle(prominent: false, height: 50))
                    .disabled(engine.isRunning)
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete workout", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(session)
                context.saveChanges()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct CompletedSetRow: View {
    let set: SetRecord
    let tracking: TrackingStyle
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            Text(set.isWarmup ? "W" : "\(set.index + 1)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Ink.tertiary)
                .frame(width: 22, alignment: .leading)
            Text(value)
                .font(.rowValue)
                .foregroundStyle(Ink.primary)
            Spacer(minLength: 0)
            if tracking == .weightAndReps, set.estimatedOneRepMaxKg > 0 {
                Text("e1RM \(Format.weight(set.estimatedOneRepMaxKg, in: settings.unit))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }

    private var value: String {
        switch tracking {
        case .weightAndReps:
            "\(Format.weight(set.weightKg, in: settings.unit)) \(settings.unit.short) × \(set.reps)"
        case .repsOnly:
            "\(set.reps) reps"
        case .duration:
            "\(set.seconds)s"
        }
    }
}

// MARK: - Summary

/// Shown once, right after finishing: what happened, and anything newly earned.
struct SessionSummaryView: View {
    let session: WorkoutSession
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    private var awards: [MilestoneAward] { engine.finishedAwards }
    @State private var savingRoutine = false
    @State private var savedRoutine = false
    @State private var routineName = ""

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session complete").microLabelStyle()
                        Text(session.title)
                            .font(.system(size: 28, weight: .semibold))
                            .tracking(-0.6)
                            .foregroundStyle(Ink.primary)
                    }
                    .padding(.top, 8)

                    HStack(spacing: 0) {
                        StatTile(label: "Duration", value: Format.shortDuration(session.duration))
                        StatTile(label: "Sets", value: "\(session.workingSets.count)")
                        StatTile(label: "Reps", value: "\(session.totalReps)")
                        StatTile(
                            label: "Volume",
                            value: Format.volume(session.volumeKg, in: settings.unit),
                            unit: settings.unit.short
                        )
                    }

                    if !awards.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("New milestones")
                            ForEach(awards) { award in
                                AwardBanner(award: award, unit: settings.unit)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Logged")
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(session.orderedBlocks.enumerated()), id: \.element.id) { index, block in
                                    if index > 0 { Hairline(inset: 18) }
                                    HStack {
                                        Text(block.name)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Ink.primary)
                                        Spacer()
                                        Text("\(block.completedCount) × sets")
                                            .font(.system(size: 13).monospacedDigit())
                                            .foregroundStyle(Ink.tertiary)
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                }
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if !savedRoutine {
                            Button("Save as routine") { savingRoutine = true }
                                .buttonStyle(InkButtonStyle(prominent: false, height: 50))
                        } else {
                            Text("Saved to routines")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Ink.tertiary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        Button("Done") {
                            engine.clearFinished()
                            dismiss()
                        }
                        .buttonStyle(InkButtonStyle())
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.large])
        .alert("Save as routine", isPresented: $savingRoutine) {
            TextField("Routine name", text: $routineName)
            Button("Save") {
                let name = routineName.trimmingCharacters(in: .whitespaces)
                engine.saveAsRoutine(session, named: name.isEmpty ? session.title : name, for: session.athlete)
                savedRoutine = true
                routineName = ""
            }
            Button("Cancel", role: .cancel) { routineName = "" }
        } message: {
            Text("Next time it starts pre-filled with these exercises and sets.")
        }
        .onAppear { routineName = session.title }
    }
}
