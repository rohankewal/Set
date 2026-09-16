import SwiftData
import SwiftUI

struct TodayView: View {
    let athlete: Athlete?
    @Binding var showingWorkout: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine

    @State private var showingSettings = false
    @State private var showingAthletes = false
    @State private var showingMilestones = false
    @State private var showingRoutines = false

    private var sessions: [WorkoutSession] { athlete?.completedSessions ?? [] }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        storageWarning
                        primaryAction
                        routinesSection
                        weekCard
                        statRow
                        milestoneCard
                        lastSessionCard
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingAthletes) { AthleteSwitcher() }
        .sheet(isPresented: $showingMilestones) { MilestonesView(athlete: athlete) }
        .sheet(isPresented: $showingRoutines) {
            RoutinesView(athlete: athlete) { routine in
                engine.start(routine: routine, for: athlete)
                showingWorkout = true
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .microLabelStyle()
                Text("Set")
                    .font(.system(size: 32, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(Ink.primary)
            }
            Spacer()
            HStack(spacing: 10) {
                Button { showingAthletes = true } label: {
                    Text(athlete?.initials ?? "—")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(IconButtonStyle(size: 36))
                .accessibilityLabel("Switch athlete")

                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(IconButtonStyle(size: 36))
                .accessibilityLabel("Settings")
            }
        }
        .padding(.top, 14)
    }

    // MARK: Start / resume

    private var primaryAction: some View {
        VStack(spacing: 12) {
            if engine.isRunning {
                Button {
                    showingWorkout = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.forward")
                        Text("Resume workout")
                    }
                }
                .buttonStyle(InkButtonStyle(height: 58))

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsedCaption)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Ink.tertiary)
                }
            } else {
                Button {
                    engine.start(for: athlete)
                    showingWorkout = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                        Text("Start workout")
                    }
                }
                .buttonStyle(InkButtonStyle(height: 58))

                if let last = sessions.first {
                    Button {
                        engine.repeatSession(last, for: athlete)
                        showingWorkout = true
                    } label: {
                        Text("Repeat “\(last.title)”")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private var elapsedCaption: String {
        guard let started = engine.session?.startedAt else { return "" }
        let sets = engine.session?.completedSets.count ?? 0
        return "\(Format.clock(Date.now.timeIntervalSince(started))) · \(sets) set\(sets == 1 ? "" : "s") logged"
    }

    /// Only ever visible when writes are failing — which is precisely when the
    /// user needs to know, before they log a month of workouts into nothing.
    @ViewBuilder
    private var storageWarning: some View {
        if let warning = StoreHealth.shared.warning {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .medium))
                Text(warning)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Ink.onAccent)
            .padding(14)
            .background(Ink.accent, in: .rect(cornerRadius: Metric.controlRadius, style: .continuous))
        }
    }

    // MARK: Routines

    private var routines: [Routine] {
        (athlete?.allRoutines ?? []).sorted {
            ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }

    @ViewBuilder
    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Routines") {
                Button(routines.isEmpty ? "New" : "All") { showingRoutines = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }

            if routines.isEmpty {
                Button { showingRoutines = true } label: {
                    Card {
                        Text("Save a finished workout as a routine and it starts pre-filled next time — exercises, sets and target reps.")
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(routines.prefix(3).enumerated()), id: \.element.id) { index, routine in
                            if index > 0 { Hairline(inset: 18) }
                            Button {
                                guard !engine.isRunning else { showingWorkout = true; return }
                                engine.start(routine: routine, for: athlete)
                                showingWorkout = true
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(routine.name)
                                            .font(.rowTitle)
                                            .foregroundStyle(Ink.primary)
                                        Text(routine.summary)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Ink.tertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text("\(routine.totalSets) sets")
                                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Ink.tertiary)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Ink.primary)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 13)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Week

    private var weekCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "This week") {
                    Text("\(weekSessions.count) session\(weekSessions.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Ink.secondary)
                }
                WeekStrip(trained: trainedDays, todayIndex: todayIndex)
            }
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        return calendar
    }

    private var weekSessions: [WorkoutSession] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return sessions.filter { interval.contains($0.startedAt) }
    }

    private var trainedDays: [Bool] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else {
            return Array(repeating: false, count: 7)
        }
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return false }
            return sessions.contains { calendar.isDate($0.startedAt, inSameDayAs: day) }
        }
    }

    private var todayIndex: Int {
        let weekday = calendar.component(.weekday, from: .now) // 1 = Sunday
        return (weekday + 5) % 7
    }

    // MARK: Stats

    private var statRow: some View {
        HStack(alignment: .top, spacing: 0) {
            StatTile(
                label: "Volume",
                value: Format.volume(weekSessions.reduce(0) { $0 + $1.volumeKg }, in: settings.unit),
                unit: settings.unit.short,
                caption: "this week"
            )
            Rectangle().fill(Ink.line).frame(width: Metric.hairline, height: 46)
            StatTile(
                label: "Sets",
                value: "\(weekSessions.reduce(0) { $0 + $1.workingSets.count })",
                caption: "this week"
            )
            .padding(.leading, 16)
            Rectangle().fill(Ink.line).frame(width: Metric.hairline, height: 46)
            StatTile(
                label: "Streak",
                value: "\(Stats.weekStreak(for: sessions))",
                unit: "wk",
                caption: "consecutive"
            )
            .padding(.leading, 16)
        }
    }

    // MARK: Milestones

    private var recentMilestones: [Milestone] {
        (athlete?.allMilestones ?? [])
            .filter { $0.previousValue > 0 || !$0.kind.isExerciseScoped }
            .sorted { $0.achievedAt > $1.achievedAt }
    }

    @ViewBuilder
    private var milestoneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Milestones") {
                Button("All") { showingMilestones = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }

            if recentMilestones.isEmpty {
                Card {
                    Text("Records appear here the moment you beat one — heaviest set, best estimated max, longest streak.")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(recentMilestones.prefix(3).enumerated()), id: \.element.id) { index, milestone in
                            if index > 0 { Hairline(inset: 18) }
                            MilestoneRow(milestone: milestone)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 13)
                        }
                    }
                }
            }
        }
    }

    // MARK: Last session

    @ViewBuilder
    private var lastSessionCard: some View {
        if let last = sessions.first {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Last session")
                NavigationLink {
                    SessionDetailView(session: last)
                } label: {
                    Card {
                        SessionRow(session: last)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
