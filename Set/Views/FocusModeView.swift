import SwiftData
import SwiftUI

/// One exercise, one set, nothing else.
///
/// Every other tracker is a scrolling list of cards you read while standing over
/// the bar. This puts the phone on the bench: the target is the size of your
/// palm, the next thing to do is the only thing on screen, and a swipe moves
/// between exercises. It's the same session — the list view is still there — but
/// this is the one you use with chalk on your hands.
struct FocusModeView: View {
    let session: WorkoutSession
    let athlete: Athlete?

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Field?
    @State private var flash = false

    fileprivate enum Field: Identifiable {
        case weight, reps
        var id: Int { hashValue }
    }

    private var blocks: [ExerciseBlock] { session.orderedBlocks }
    // Opens on, and moves, the engine's current exercise, so it matches the
    // list you came from and the watch.
    private var index: Int { engine.focusIndex }
    private var block: ExerciseBlock? { engine.focusedBlock }

    /// The set being worked on: first unfinished, else the last one logged.
    private var currentSet: SetRecord? {
        guard let block else { return nil }
        return block.orderedSets.first { !$0.isComplete } ?? block.orderedSets.last
    }

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()

            if let block, let set = currentSet {
                VStack(spacing: 0) {
                    header(block)
                    Spacer(minLength: 0)
                    numbers(block: block, set: set)
                    Spacer(minLength: 0)
                    logButton(block: block, set: set)
                    pager
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 14)
                .contentShape(.rect)
                .gesture(swipe)
            } else {
                EmptyState(
                    symbol: "dumbbell",
                    title: "Nothing to focus on",
                    message: "Add an exercise to the session first."
                )
            }

            if engine.isRestActive {
                restOverlay
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(item: $editing) { field in
            FocusKeypad(
                title: field == .weight ? settings.unit.short.uppercased() : "REPS",
                value: fieldValue(field),
                allowsDecimal: field == .weight,
                step: field == .weight ? settings.unit.step : 1
            ) { newValue in
                apply(newValue, to: field)
            }
        }
        .animation(Motion.snap, value: index)
        .animation(Motion.gentle, value: engine.isRestActive)
    }

    // MARK: Header

    private func header(_ block: ExerciseBlock) -> some View {
        HStack(alignment: .center) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(IconButtonStyle(size: 38))
            .accessibilityLabel("Leave focus mode")

            Spacer(minLength: 8)

            VStack(spacing: 3) {
                Text(block.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text("Set \(completedCount(block) + 1) of \(max(block.allSets.count, completedCount(block) + 1))")
                    .microLabelStyle()
            }

            Spacer(minLength: 8)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(Format.clock(Date.now.timeIntervalSince(session.startedAt)))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.top, 8)
    }

    private func completedCount(_ block: ExerciseBlock) -> Int {
        block.allSets.count { $0.isComplete && $0.kind.countsTowardVolume }
    }

    // MARK: Numbers

    private func numbers(block: ExerciseBlock, set: SetRecord) -> some View {
        VStack(spacing: 22) {
            if block.tracking.usesWeight {
                bigField(
                    value: Format.weight(set.weightKg, in: settings.unit),
                    unit: settings.unit.short,
                    field: .weight
                )
            }
            bigField(
                value: block.tracking == .duration ? "\(set.seconds)" : "\(set.reps)",
                unit: block.tracking == .duration ? "sec" : "reps",
                field: .reps
            )

            if let hint = previousHint(block) {
                Text(hint)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }

    /// Tap anywhere on the number to edit it — the whole row is the target.
    private func bigField(value: String, unit: String, field: Field) -> some View {
        Button {
            editing = field
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.readout(76, weight: .medium))
                    .readoutTracking(76)
                    .foregroundStyle(Ink.primary)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Ink.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func previousHint(_ block: ExerciseBlock) -> String? {
        guard let athlete else { return nil }
        let history = Stats.bests(for: block.name, in: athlete.allSessions, excluding: session.id)
        guard let last = history.lastSet else { return nil }
        switch block.tracking {
        case .weightAndReps:
            return "Last time · \(Format.weight(last.weightKg, in: settings.unit))\(settings.unit.short) × \(last.reps)"
        case .repsOnly: return "Last time · \(last.reps) reps"
        case .duration: return "Last time · \(last.seconds)s"
        }
    }

    // MARK: Log

    private func logButton(block: ExerciseBlock, set: SetRecord) -> some View {
        Button {
            engine.toggleCompletion(of: set, in: block)
            withAnimation(Motion.snap) { flash = true }
            // Queue the next set so there's always something to log.
            if block.orderedSets.allSatisfy(\.isComplete) {
                engine.addSet(to: block)
            }
            Task {
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(Motion.snap) { flash = false }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .bold))
                Text("Log set")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Ink.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 128)
            .background(Ink.accent, in: .rect(cornerRadius: 28, style: .continuous))
            .scaleEffect(flash ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log set")
    }

    // MARK: Pager

    private var pager: some View {
        HStack(spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { offset, item in
                Capsule()
                    .fill(offset == index ? Ink.primary : Ink.line)
                    .frame(width: offset == index ? 18 : 6, height: 6)
                    .onTapGesture { engine.focus(on: item) }
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Exercise \(index + 1) of \(blocks.count)")
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                engine.moveFocus(by: value.translation.width < 0 ? 1 : -1)
            }
    }

    // MARK: Rest

    /// Rest takes the whole screen here. There's nothing to read mid-set, so the
    /// clock may as well be the size of the phone.
    private var restOverlay: some View {
        ZStack {
            Ink.canvas.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 26) {
                Text(engine.isRestPaused ? "PAUSED" : "REST")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(4)
                    .foregroundStyle(Ink.tertiary)

                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    Text(Format.clock(engine.restRemaining))
                        .font(.readout(96, weight: .medium))
                        .readoutTracking(96)
                        .foregroundStyle(Ink.primary)
                        .contentTransition(.numericText(countsDown: true))
                }

                HStack(spacing: 12) {
                    Button("−15") { engine.adjustRest(by: -15) }
                        .buttonStyle(QuietButtonStyle(horizontal: 18, vertical: 12))
                    Button(engine.isResting ? "Pause" : "Resume") { engine.toggleRest() }
                        .buttonStyle(QuietButtonStyle(horizontal: 22, vertical: 12))
                    Button("+15") { engine.adjustRest(by: 15) }
                        .buttonStyle(QuietButtonStyle(horizontal: 18, vertical: 12))
                }

                Button("Skip rest") { engine.endRest() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .transition(.opacity)
        .contentShape(.rect)
        .onTapGesture { engine.toggleRest() }
    }

    // MARK: Editing

    private func fieldValue(_ field: Field) -> Double {
        guard let set = currentSet, let block else { return 0 }
        switch field {
        case .weight: return settings.unit.fromKilograms(set.weightKg)
        case .reps: return Double(block.tracking == .duration ? set.seconds : set.reps)
        }
    }

    private func apply(_ value: Double, to field: Field) {
        guard let set = currentSet, let block else { return }
        switch field {
        case .weight: set.weightKg = settings.unit.toKilograms(value)
        case .reps:
            if block.tracking == .duration {
                set.seconds = Int(value.rounded())
            } else {
                set.reps = Int(value.rounded())
            }
        }
    }
}

// MARK: - Keypad

/// A deliberately oversized number pad. Nothing here is smaller than a thumb in
/// a glove.
struct FocusKeypad: View {
    let title: String
    let value: Double
    var allowsDecimal = true
    var step: Double = 1
    let commit: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(title).microLabelStyle()
                Text(text.isEmpty ? "0" : text)
                    .font(.readout(56, weight: .medium))
                    .foregroundStyle(text.isEmpty ? Ink.tertiary : Ink.primary)
                    .contentTransition(.numericText())
            }
            .padding(.top, 22)

            HStack(spacing: 10) {
                Button("−\(Format.number(step))") { nudge(-step) }
                    .buttonStyle(QuietButtonStyle(horizontal: 18, vertical: 10))
                Button("+\(Format.number(step))") { nudge(step) }
                    .buttonStyle(QuietButtonStyle(horizontal: 18, vertical: 10))
            }

            VStack(spacing: 8) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { key in
                            Button {
                                press(key)
                            } label: {
                                Text(key)
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(Ink.primary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 62)
                                    .background(Ink.surface, in: .rect(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(key == "." && !allowsDecimal)
                            .opacity(key == "." && !allowsDecimal ? 0.3 : 1)
                        }
                    }
                }
            }

            Button("Done") {
                commit(parsed)
                dismiss()
            }
            .buttonStyle(InkButtonStyle(height: 56))
            .padding(.top, 2)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.bottom, 18)
        .background(Ink.canvas)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .onAppear { text = value > 0 ? Format.number(value) : "" }
    }

    private var parsed: Double {
        max(0, Double(text) ?? value)
    }

    private func press(_ key: String) {
        Haptics.play(.tick)
        switch key {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case ".": if allowsDecimal, !text.contains(".") { text += text.isEmpty ? "0." : "." }
        default: if text.count < 6 { text += key }
        }
    }

    private func nudge(_ delta: Double) {
        let updated = max(0, parsed + delta)
        text = Format.number(updated)
        Haptics.play(.tick)
    }
}
