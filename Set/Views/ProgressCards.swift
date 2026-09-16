import Charts
import SwiftData
import SwiftUI

// MARK: - Consistency

/// Seventeen weeks of training as one small block of marks. Intensity is the
/// number of working sets that day, in four steps of grey — enough to read the
/// shape of a training year without turning the app into a colour chart.
struct ConsistencyGrid: View {
    let days: [(day: Date, sets: Int)]

    private let columns = 17
    private let cell: CGFloat = 13
    private let gap: CGFloat = 3

    private var weeks: [[(day: Date, sets: Int)]] {
        stride(from: 0, to: days.count, by: 7).map {
            Array(days[$0..<min($0 + 7, days.count)])
        }
    }

    private var peak: Int {
        max(days.map(\.sets).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, entry in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(fill(for: entry.sets))
                                .frame(width: cell, height: cell)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(Ink.line, lineWidth: entry.sets == 0 ? Metric.hairline : 0)
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Text("Less").font(.system(size: 10)).foregroundStyle(Ink.tertiary)
                ForEach(0..<4, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(shade(step))
                        .frame(width: 9, height: 9)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(Ink.line, lineWidth: step == 0 ? Metric.hairline : 0)
                        }
                }
                Text("More").font(.system(size: 10)).foregroundStyle(Ink.tertiary)
            }
        }
    }

    private func fill(for sets: Int) -> Color {
        guard sets > 0 else { return .clear }
        let ratio = Double(sets) / Double(peak)
        switch ratio {
        case ..<0.34: return shade(1)
        case ..<0.67: return shade(2)
        default: return shade(3)
        }
    }

    private func shade(_ step: Int) -> Color {
        switch step {
        case 0: .clear
        case 1: Ink.primary.opacity(0.28)
        case 2: Ink.primary.opacity(0.58)
        default: Ink.primary
        }
    }
}

// MARK: - Muscle split

/// Weekly hard sets per muscle group. Programmes are written in sets, not
/// kilograms, so this is the number that tells you whether the week was balanced.
struct MuscleSplitCard: View {
    let loads: [Stats.MuscleLoad]

    private var peak: Int { max(loads.map(\.sets).max() ?? 1, 1) }
    private var total: Int { loads.reduce(0) { $0 + $1.sets } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sets per muscle") {
                Text("\(total) this week")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.secondary)
            }
            Card {
                if loads.isEmpty {
                    Text("Nothing logged in the last seven days.")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.tertiary)
                } else {
                    VStack(spacing: 12) {
                        ForEach(loads) { load in
                            HStack(spacing: 12) {
                                Text(load.muscle.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Ink.secondary)
                                    .frame(width: 74, alignment: .leading)
                                ThinBar(progress: Double(load.sets) / Double(peak), height: 7)
                                Text("\(load.sets)")
                                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Ink.primary)
                                    .frame(width: 24, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Body weight

struct BodyWeightCard: View {
    let athlete: Athlete?

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @State private var logging = false

    private var entries: [BodyEntry] {
        (athlete?.allBodyEntries ?? []).sorted { $0.date < $1.date }
    }

    private var latest: BodyEntry? { entries.last }

    private var change: Double? {
        guard let latest, let first = entries.first, entries.count > 1 else { return nil }
        return latest.weightKg - first.weightKg
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Body weight") {
                Button("Log") { logging = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.secondary)
            }
            Card {
                if entries.isEmpty {
                    Text("Log your weight now and then — strength per kilo is the number that actually moves.")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Readout(
                                value: Format.weight(latest?.weightKg ?? 0, in: settings.unit),
                                unit: settings.unit.short,
                                size: 30
                            )
                            if let change, abs(change) > 0.05 {
                                Text("\(change > 0 ? "+" : "−")\(Format.weight(abs(change), in: settings.unit)) \(settings.unit.short)")
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Ink.tertiary)
                            }
                            Spacer()
                        }

                        if entries.count > 1 {
                            Chart(entries) { entry in
                                LineMark(
                                    x: .value("Date", entry.date),
                                    y: .value("Weight", settings.unit.fromKilograms(entry.weightKg))
                                )
                                .foregroundStyle(Ink.primary)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .interpolationMethod(.monotone)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartXAxis(.hidden)
                            .chartYAxis {
                                AxisMarks(position: .trailing, values: .automatic(desiredCount: 2)) { _ in
                                    AxisGridLine().foregroundStyle(Ink.line)
                                    AxisValueLabel()
                                        .font(.system(size: 10).monospacedDigit())
                                        .foregroundStyle(Ink.tertiary)
                                }
                            }
                            .frame(height: 90)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $logging) {
            BodyWeightSheet(athlete: athlete)
        }
    }
}

private struct BodyWeightSheet: View {
    let athlete: Athlete?

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var value: Double = 0
    @FocusState private var focused: Bool
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Screen {
                VStack(spacing: 20) {
                    Text("Today").microLabelStyle()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TextField("0", text: $text)
                            .focused($focused)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.readout(52, weight: .medium))
                            .foregroundStyle(Ink.primary)
                            .frame(width: 150)
                        Text(settings.unit.short)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Ink.tertiary)
                    }

                    Button("Save") {
                        let entered = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
                        engine.logBodyWeight(settings.unit.toKilograms(entered), for: athlete)
                        dismiss()
                    }
                    .buttonStyle(InkButtonStyle())
                    .disabled(Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 <= 0)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 24)
            }
            .navigationTitle("Body weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let existing = athlete?.bodyweightKg, existing > 0 {
                    text = Format.weight(existing, in: settings.unit)
                }
                focused = true
            }
        }
        .presentationDetents([.height(320)])
    }
}

// MARK: - The read

/// The coaching read. Every number on screen was computed in Swift; when Apple
/// Intelligence is available it writes the sentence over the top, and the facts
/// stay visible underneath either way — the point is that you can check it.
struct InsightsCard: View {
    let digest: TrainingDigest

    @Environment(AppSettings.self) private var settings
    @State private var narrator = CoachNarrator()
    @State private var showingFacts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "The read") {
                if narrator.isRefining {
                    Text("refining")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.tertiary)
                        .transition(.opacity)
                } else if narrator.isGenerated {
                    Label("On device", systemImage: "apple.intelligence")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.tertiary)
                        .labelStyle(.titleAndIcon)
                        .transition(.opacity)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    switch narrator.state {
                    case let .ready(headline, detail):
                        VStack(alignment: .leading, spacing: 6) {
                            Text(headline)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(Ink.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detail)
                                .font(.system(size: 14))
                                .foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .transition(.opacity)

                    default:
                        Text("Finish a session or two and a read will appear here.")
                            .font(.system(size: 14))
                            .foregroundStyle(Ink.tertiary)
                    }

                    Hairline()

                    numbers

                    Button {
                        withAnimation(Motion.snap) { showingFacts.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showingFacts ? "Hide the working" : "Show the working")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(showingFacts ? 180 : 0))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ink.tertiary)
                    }
                    .buttonStyle(.plain)

                    if showingFacts {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(digest.factLines(unit: settings.unit), id: \.self) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Ink.line)
                                        .frame(width: 3, height: 3)
                                        .padding(.top, 6)
                                    Text(line)
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(Ink.tertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if let message = narrator.availabilityMessage {
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Ink.tertiary)
                                    .padding(.top, 4)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .task(id: digest) {
            await narrator.narrate(digest, unit: settings.unit)
        }
        .animation(Motion.gentle, value: showingFacts)
        .animation(Motion.gentle, value: narrator.state)
        .animation(Motion.tick, value: narrator.isRefining)
    }

    /// Density and rest adherence: two numbers the other trackers don't show.
    private var numbers: some View {
        HStack(spacing: 0) {
            StatTile(
                label: "Density",
                value: Format.volume(digest.density, in: settings.unit),
                unit: "\(settings.unit.short)/min",
                caption: densityCaption
            )
            if let rest = digest.medianRest {
                StatTile(
                    label: "Rest taken",
                    value: Format.clock(rest),
                    caption: restCaption
                )
            }
            if digest.suggestsDeload {
                StatTile(label: "Flag", value: "Deload", caption: "volume up, strength flat")
            } else {
                StatTile(label: "Sets / week", value: "\(digest.setsPerWeek)", caption: setsCaption)
            }
        }
    }

    private var densityCaption: String? {
        guard let change = digest.densityChange else { return "last \(digest.sessionsAnalysed) sessions" }
        let percent = Int((abs(change) * 100).rounded())
        guard percent > 0 else { return "flat vs before" }
        return "\(change > 0 ? "+" : "−")\(percent)% vs before"
    }

    private var restCaption: String? {
        guard let actual = digest.medianRest, let planned = digest.plannedRest else { return nil }
        let delta = actual - planned
        if abs(delta) < 10 { return "on the timer" }
        return delta > 0 ? "\(Int(delta))s over timer" : "\(Int(-delta))s under timer"
    }

    private var setsCaption: String? {
        guard let change = digest.setsPerWeekChange, change != 0 else { return "working sets" }
        return "\(change > 0 ? "+" : "")\(change) vs before"
    }
}
