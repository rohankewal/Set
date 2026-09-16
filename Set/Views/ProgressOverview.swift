import Charts
import SwiftData
import SwiftUI

struct ProgressOverview: View {
    let athlete: Athlete?
    @Environment(AppSettings.self) private var settings

    private var sessions: [WorkoutSession] { athlete?.completedSessions ?? [] }

    private var weekly: [(weekStart: Date, volumeKg: Double, sessions: Int)] {
        Stats.weeklyVolume(for: sessions)
    }

    /// Top movements by estimated max, which is the closest thing to "how strong
    /// am I" the app can compute from logged sets alone.
    private var leaders: [(name: String, bests: ExerciseBests)] {
        let names = Set(sessions.flatMap { $0.orderedBlocks.map(\.name) })
        return names
            .map { (name: $0, bests: Stats.bests(for: $0, in: sessions)) }
            .filter { $0.bests.estimatedMaxKg > 0 || $0.bests.bestReps > 0 }
            .sorted { $0.bests.estimatedMaxKg > $1.bests.estimatedMaxKg }
    }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if sessions.isEmpty {
                            EmptyState(
                                symbol: "chart.bar",
                                title: "Nothing to plot yet",
                                message: "Finish a workout and your weekly volume, records and streak show up here."
                            )
                        } else {
                            statRow
                            InsightsCard(digest: Insights.digest(for: sessions))
                            consistency
                            volumeChart
                            MuscleSplitCard(loads: Stats.muscleSplit(for: sessions))
                            BodyWeightCard(athlete: athlete)
                            recordsSection
                            milestonesLink
                        }
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Progress")
        }
    }

    private var statRow: some View {
        HStack(spacing: 0) {
            StatTile(label: "Sessions", value: "\(sessions.count)")
            StatTile(label: "Streak", value: "\(Stats.weekStreak(for: sessions))", unit: "wk")
            StatTile(
                label: "Lifetime",
                value: Format.volume(Stats.lifetimeVolume(for: sessions), in: settings.unit),
                unit: settings.unit.short
            )
        }
        .padding(.top, 4)
    }

    private var consistency: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Consistency") {
                Text("^[\(Stats.bestDayStreak(for: sessions)) day](inflect: true) best run")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.secondary)
            }
            Card {
                ScrollView(.horizontal) {
                    ConsistencyGrid(days: Stats.dailyLoad(for: sessions))
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing)
            }
        }
    }

    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Weekly volume") {
                Text("8 weeks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }
            Card {
                Chart(weekly, id: \.weekStart) { week in
                    BarMark(
                        x: .value("Week", week.weekStart, unit: .weekOfYear),
                        y: .value("Volume", settings.unit.fromKilograms(week.volumeKg)),
                        width: .fixed(14)
                    )
                    .foregroundStyle(week.sessions == 0 ? Ink.line : Ink.primary)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { value in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(Ink.line)
                        AxisValueLabel()
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(Ink.tertiary)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Strongest lifts")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(leaders.prefix(6).enumerated()), id: \.element.name) { index, leader in
                        if index > 0 { Hairline(inset: 18) }
                        NavigationLink {
                            ExerciseProgressView(exerciseName: leader.name, athlete: athlete)
                                .navigationTransition(.crossFade)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(leader.name)
                                        .font(.rowTitle)
                                        .foregroundStyle(Ink.primary)
                                    Text(detail(for: leader.bests))
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(Ink.tertiary)
                                }
                                Spacer(minLength: 0)
                                if leader.bests.estimatedMaxKg > 0 {
                                    Readout(
                                        value: Format.weight(leader.bests.estimatedMaxKg, in: settings.unit),
                                        unit: settings.unit.short,
                                        size: 18
                                    )
                                } else {
                                    // Bodyweight movements have no load to report.
                                    Readout(value: "\(leader.bests.bestReps)", unit: "reps", size: 18)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Ink.tertiary)
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

    private func detail(for bests: ExerciseBests) -> String {
        var parts: [String] = []
        if bests.heaviestKg > 0 {
            parts.append("Top \(Format.weight(bests.heaviestKg, in: settings.unit))\(settings.unit.short)")
        }
        if bests.bestReps > 0 { parts.append("\(bests.bestReps) rep best") }
        return parts.isEmpty ? "No working sets yet" : parts.joined(separator: " · ")
    }

    private var milestonesLink: some View {
        NavigationLink {
            MilestonesView(athlete: athlete).navigationTransition(.crossFade)
        } label: {
            HStack {
                Text("All milestones")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Ink.primary)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(Ink.surface, in: .rect(cornerRadius: Metric.controlRadius + 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.controlRadius + 2, style: .continuous)
                    .strokeBorder(Ink.line, lineWidth: Metric.hairline)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Single exercise

struct ExerciseProgressView: View {
    let exerciseName: String
    let athlete: Athlete?
    @Environment(AppSettings.self) private var settings

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let estimatedMax: Double
        let topSet: Double
    }

    private var sessions: [WorkoutSession] { athlete?.completedSessions ?? [] }

    private var points: [Point] {
        sessions
            .compactMap { session -> Point? in
                let sets = session.orderedBlocks
                    .filter { $0.name == exerciseName }
                    .flatMap { $0.allSets }
                    .filter { $0.isComplete && !$0.isWarmup }
                guard !sets.isEmpty else { return nil }
                return Point(
                    date: session.startedAt,
                    estimatedMax: sets.map(\.estimatedOneRepMaxKg).max() ?? 0,
                    topSet: sets.map(\.weightKg).max() ?? 0
                )
            }
            .sorted { $0.date < $1.date }
    }

    private var bests: ExerciseBests { Stats.bests(for: exerciseName, in: sessions) }

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 0) {
                        StatTile(
                            label: "Heaviest",
                            value: Format.weight(bests.heaviestKg, in: settings.unit),
                            unit: settings.unit.short
                        )
                        StatTile(
                            label: "Est. max",
                            value: Format.weight(bests.estimatedMaxKg, in: settings.unit),
                            unit: settings.unit.short
                        )
                        StatTile(label: "Best reps", value: "\(bests.bestReps)")
                    }
                    .padding(.top, 4)

                    if points.count > 1 {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader("Estimated max")
                            Card {
                                Chart(points) { point in
                                    AreaMark(
                                        x: .value("Date", point.date),
                                        y: .value("e1RM", settings.unit.fromKilograms(point.estimatedMax))
                                    )
                                    .foregroundStyle(
                                        .linearGradient(
                                            colors: [Ink.primary.opacity(0.18), Ink.primary.opacity(0.01)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    LineMark(
                                        x: .value("Date", point.date),
                                        y: .value("e1RM", settings.unit.fromKilograms(point.estimatedMax))
                                    )
                                    .foregroundStyle(Ink.primary)
                                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .interpolationMethod(.monotone)
                                }
                                .chartYScale(domain: .automatic(includesZero: false))
                                .chartXAxis {
                                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                            .font(.system(size: 10))
                                            .foregroundStyle(Ink.tertiary)
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                                        AxisGridLine().foregroundStyle(Ink.line)
                                        AxisValueLabel()
                                            .font(.system(size: 10).monospacedDigit())
                                            .foregroundStyle(Ink.tertiary)
                                    }
                                }
                                .frame(height: 170)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Session by session")
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(points.reversed().enumerated()), id: \.element.id) { index, point in
                                    if index > 0 { Hairline(inset: 18) }
                                    HStack {
                                        Text(point.date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits)))
                                            .font(.system(size: 14).monospacedDigit())
                                            .foregroundStyle(Ink.secondary)
                                        Spacer()
                                        Text("top \(Format.weight(point.topSet, in: settings.unit))\(settings.unit.short)")
                                            .font(.system(size: 13).monospacedDigit())
                                            .foregroundStyle(Ink.tertiary)
                                        Readout(
                                            value: Format.weight(point.estimatedMax, in: settings.unit),
                                            size: 15
                                        )
                                        .frame(width: 54, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
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
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
