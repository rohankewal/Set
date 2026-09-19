import SwiftData
import SwiftUI

struct ExerciseBlockCard: View {
    @Bindable var block: ExerciseBlock
    let athlete: Athlete?

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine

    private var tracking: TrackingStyle { block.tracking }
    /// Resolved once per exercise rather than on every keystroke — scanning the
    /// full history in `body` would make set entry feel heavy on a long log.
    @State private var lastTimeCaption = ""
    @State private var suggestion: String?
    @State private var editingNote = false

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                header
                if !block.notes.isEmpty {
                    noteLine
                }
                Hairline(inset: 18)
                columnTitles
                ForEach(block.orderedSets) { set in
                    SetRow(set: set, block: block)
                }
                Hairline(inset: 18)
                footer
            }
        }
        .overlay(alignment: .leading) {
            // A rule down the side is all a superset needs to read as one unit.
            if block.supersetGroup != nil {
                Rectangle()
                    .fill(Ink.primary)
                    .frame(width: 2)
                    .padding(.vertical, 14)
            }
        }
        .task(id: block.name) {
            lastTimeCaption = resolveLastTimeCaption()
            suggestion = resolveSuggestion()
        }
        .sheet(isPresented: $editingNote) {
            NoteEditor(title: block.name, text: Binding(
                get: { block.notes },
                set: { block.notes = $0 }
            ))
        }
        .contextMenu {
            Button("Add set", systemImage: "plus") { engine.addSet(to: block) }
            Button("Add warm-up ramp", systemImage: "flame") { engine.addWarmupSets(to: block) }
            Button(block.notes.isEmpty ? "Add note" : "Edit note", systemImage: "text.alignleft") {
                editingNote = true
            }
            if block.supersetGroup == nil, let next = nextBlock {
                Button("Superset with \(next.name)", systemImage: "link") {
                    engine.groupSuperset([block, next])
                }
            }
            if block.supersetGroup != nil {
                Button("Break superset", systemImage: "link.badge.plus") {
                    engine.ungroupSuperset(block)
                }
            }
            Menu("Rest timer") {
                ForEach([45, 60, 90, 120, 180, 240], id: \.self) { seconds in
                    Button(seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m\(seconds % 60 == 0 ? "" : " \(seconds % 60)s")") {
                        block.restSeconds = seconds
                    }
                }
            }
            Button("Remove exercise", systemImage: "trash", role: .destructive) {
                engine.remove(block)
            }
        }
    }

    // MARK: Header

    private var nextBlock: ExerciseBlock? {
        guard let session = block.session else { return nil }
        let ordered = session.orderedBlocks
        guard let index = ordered.firstIndex(of: block), index + 1 < ordered.count else { return nil }
        let candidate = ordered[index + 1]
        return candidate.supersetGroup == nil ? candidate : nil
    }

    /// "A1", "A2" — group letter and position within it.
    private var supersetTag: String? {
        guard let group = block.supersetGroup, let session = block.session else { return nil }
        let groups = session.orderedBlocks.compactMap(\.supersetGroup)
        let uniqueOrdered = groups.reduce(into: [Int]()) { partial, value in
            if !partial.contains(value) { partial.append(value) }
        }
        guard let letterIndex = uniqueOrdered.firstIndex(of: group),
              let scalar = UnicodeScalar(65 + letterIndex) else { return nil }
        let peers = block.supersetPeers(in: session)
        let position = (peers.firstIndex(of: block) ?? 0) + 1
        return "\(Character(scalar))\(position)"
    }

    private var noteLine: some View {
        Text(block.notes)
            .font(.system(size: 13))
            .foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .onTapGesture { editingNote = true }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if let supersetTag {
                        Text(supersetTag)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Ink.onAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Ink.accent, in: .rect(cornerRadius: 4, style: .continuous))
                    }
                    Text(block.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                }
                Text(lastTimeCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("\(block.completedCount)/\(block.allSets.count)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(block.isFinished ? Ink.primary : Ink.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Ink.surfaceHigh, in: .capsule)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private func resolveLastTimeCaption() -> String {
        guard let athlete else { return block.exercise?.subtitle ?? "" }
        let history = Stats.bests(for: block.name, in: athlete.allSessions, excluding: block.session?.id)
        guard let last = history.lastSet else { return block.exercise?.subtitle ?? "" }
        switch tracking {
        case .weightAndReps:
            return "Last · \(Format.weight(last.weightKg, in: settings.unit))\(settings.unit.short) × \(last.reps)"
        case .repsOnly:
            return "Last · \(last.reps) reps"
        case .duration:
            return "Last · \(last.seconds)s"
        }
    }

    // MARK: Columns

    private var columnTitles: some View {
        HStack(spacing: 10) {
            Text("Set").microLabelStyle().frame(width: 28, alignment: .leading)
            if tracking.usesWeight {
                Text(settings.unit.short).microLabelStyle().frame(width: 78, alignment: .center)
            }
            Text(tracking == .duration ? "Seconds" : "Reps")
                .microLabelStyle()
                .frame(width: tracking.usesWeight ? 66 : 96, alignment: .center)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Ink.tertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                engine.addSet(to: block)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Add set")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.primary)
            }
            .buttonStyle(.plain)

            if let suggestion, !block.isFinished {
                Button {
                    applySuggestion()
                } label: {
                    Text(suggestion)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Ink.surfaceHigh, in: .capsule)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Menu {
                ForEach([30, 45, 60, 90, 120, 180, 240], id: \.self) { seconds in
                    Button(restLabel(seconds)) { block.restSeconds = seconds }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .medium))
                    Text(restLabel(block.restSeconds))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(Ink.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    /// The suggestion is advice, not autopilot: tapping it fills the next
    /// unlogged set, and nothing happens until you do.
    private func applySuggestion() {
        guard let athlete,
              let target = block.orderedSets.first(where: { !$0.isComplete && $0.kind != .warmup })
                  ?? block.orderedSets.last(where: { !$0.isComplete })
        else { return }
        let history = Stats.bests(for: block.name, in: athlete.allSessions, excluding: block.session?.id)
        guard let last = history.lastSet else { return }
        switch tracking {
        case .weightAndReps:
            if last.reps >= 8 {
                target.weightKg = PlateMath.round(
                    last.weightKg + settings.unit.toKilograms(settings.unit.step),
                    to: settings.unit
                )
                target.reps = max(1, last.reps - 2)
            } else {
                target.weightKg = last.weightKg
                target.reps = last.reps + 1
            }
        case .repsOnly:
            target.reps = last.reps + 1
        case .duration:
            target.seconds = last.seconds + 5
        }
        Haptics.play(.tick)
    }

    private func resolveSuggestion() -> String? {
        guard let athlete else { return nil }
        let history = Stats.bests(for: block.name, in: athlete.allSessions, excluding: block.session?.id)
        return Progression.suggestion(for: history, tracking: tracking, unit: settings.unit)
    }

    private func restLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : (seconds % 60 == 0 ? "\(seconds / 60)m" : "\(seconds / 60)m \(seconds % 60)s")
    }
}

// MARK: - Set row

struct SetRow: View {
    @Bindable var set: SetRecord
    let block: ExerciseBlock

    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @State private var showingPlates = false

    private var tracking: TrackingStyle { block.tracking }

    var body: some View {
        HStack(spacing: 10) {
            Text(set.kind == .working ? "\(workingNumber)" : set.kind.badge)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(set.kind == .working ? Ink.secondary : Ink.tertiary)
                .frame(width: 28, alignment: .leading)

            if tracking.usesWeight {
                NumberField(
                    value: settings.unit.fromKilograms(set.weightKg),
                    placeholder: "0",
                    allowsDecimal: true,
                    width: 78,
                    step: settings.unit.step
                ) { new in
                    set.weightKg = settings.unit.toKilograms(new)
                    // Logged sets stay editable: you did six of the eight you
                    // wrote down. Any records the set earned are re-checked.
                    engine.setDidChange(set, in: block)
                }
            }

            NumberField(
                value: Double(tracking == .duration ? set.seconds : set.reps),
                placeholder: "0",
                allowsDecimal: false,
                width: tracking.usesWeight ? 66 : 96,
                step: tracking == .duration ? 5 : 1
            ) { new in
                if tracking == .duration {
                    set.seconds = Int(new.rounded())
                } else {
                    set.reps = Int(new.rounded())
                }
                engine.setDidChange(set, in: block)
            }

            Spacer(minLength: 0)

            if let rpe = set.rpe {
                Text("@\(Format.number(rpe))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
            }

            Button {
                engine.toggleCompletion(of: set, in: block)
            } label: {
                CheckBadge(isOn: set.isComplete)
            }
            .buttonStyle(.plain)
            .frame(width: 34, alignment: .trailing)
            .accessibilityLabel(set.isComplete ? "Mark set incomplete" : "Complete set")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background {
            if set.isComplete {
                Ink.surfaceHigh.opacity(0.55)
            }
        }
        .contentShape(.rect)
        .modifier(SwipeToDelete {
            withAnimation(Motion.snap) { engine.remove(set, from: block) }
        })
        .contextMenu {
            Menu("Set type") {
                ForEach(SetKind.allCases, id: \.self) { kind in
                    Button {
                        set.kind = kind
                        Haptics.play(.tick)
                    } label: {
                        Label(kind.label, systemImage: set.kind == kind ? "checkmark" : "circle")
                    }
                }
            }
            Menu("Effort (RPE)") {
                Button("Not recorded") { set.rpe = nil }
                ForEach([6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5, 10.0], id: \.self) { value in
                    Button(Format.number(value)) { set.rpe = value }
                }
            }
            if block.equipmentUsesBar, set.weightKg > 0 {
                Button("Plate calculator", systemImage: "circle.circle") { showingPlates = true }
            }
            Button("Duplicate set", systemImage: "plus.square.on.square") {
                engine.addSet(to: block, kind: set.kind)
            }
            Button("Delete set", systemImage: "trash", role: .destructive) {
                engine.remove(set, from: block)
            }
        }
        .sheet(isPresented: $showingPlates) {
            PlateCalculatorView(totalKg: set.weightKg)
        }
        .animation(Motion.snap, value: set.isComplete)
        .animation(Motion.tick, value: set.kindRaw)
    }

    /// Working sets are numbered 1, 2, 3… ignoring warm-ups, the way a programme
    /// is written.
    private var workingNumber: Int {
        block.orderedSets
            .filter { $0.kind == .working }
            .firstIndex(where: { $0.id == set.id })
            .map { $0 + 1 } ?? set.index + 1
    }
}

// MARK: - Swipe to delete

/// Swipe left to reveal Delete, or all the way across to delete at once.
/// Built by hand because set rows live in cards, not a `List`, where
/// `swipeActions` would do this. Vertical drags are left to the scroll view.
private struct SwipeToDelete: ViewModifier {
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    /// Where the row rests between drags: closed, or open on the button.
    @State private var resting: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var isHorizontal: Bool?

    private let reveal: CGFloat = 84

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(action: delete) {
                    VStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Delete")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Ink.onAccent)
                    .frame(width: max(reveal, -offset))
                    .frame(maxHeight: .infinity)
                    .background(Ink.accent)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }

            content
                .background(Ink.surface)
                .overlay {
                    // While open, a tap anywhere on the row closes it rather
                    // than landing in a field.
                    if resting != 0 {
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture { close() }
                    }
                }
                .offset(x: offset)
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .simultaneousGesture(drag)
        .accessibilityAction(named: "Delete set", delete)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if isHorizontal == nil {
                    isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                }
                guard isHorizontal == true else { return }
                offset = min(0, resting + value.translation.width)
            }
            .onEnded { value in
                defer { isHorizontal = nil }
                guard isHorizontal == true else { return }
                let dragged = -(resting + value.translation.width)
                let projected = -(resting + value.predictedEndTranslation.width)
                if dragged > width * 0.6 {
                    delete()
                } else if projected > reveal / 2 {
                    withAnimation(Motion.snap) { offset = -reveal; resting = -reveal }
                    Haptics.play(.tick)
                } else {
                    close()
                }
            }
    }

    private func close() {
        withAnimation(Motion.snap) { offset = 0; resting = 0 }
    }

    private func delete() {
        Haptics.play(.warning)
        withAnimation(Motion.snap) { offset = -width }
        onDelete()
    }
}

// MARK: - Numeric field

/// A number entry that reads as plain text until touched. Values commit on blur
/// so a half-typed number never lands in the store.
struct NumberField: View {
    let value: Double
    let placeholder: String
    var allowsDecimal = true
    var width: CGFloat = 74
    var step: Double = 1
    let commit: (Double) -> Void

    @FocusState private var focused: Bool
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.readout(18, weight: .medium))
            .foregroundStyle(Ink.primary)
            .frame(width: width, height: 38)
            .background(
                focused ? Ink.surfaceHigh : Color.clear,
                in: .rect(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(focused ? Ink.primary.opacity(0.5) : Ink.line, lineWidth: Metric.hairline)
            }
            .task(id: value) { if !focused { text = display } }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    text = value == 0 ? "" : display
                } else {
                    commitText()
                }
            }
            .toolbar {
                if focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Button("−\(Format.number(step))") { nudge(-step) }
                        Button("+\(Format.number(step))") { nudge(step) }
                        Spacer()
                        Button("Done") { focused = false }
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .animation(Motion.tick, value: focused)
    }

    private var display: String { Format.number(value) }

    private func nudge(_ delta: Double) {
        let current = Double(text.replacingOccurrences(of: ",", with: ".")) ?? value
        let updated = max(0, current + delta)
        text = Format.number(updated)
        commit(updated)
        Haptics.play(.tick)
    }

    private func commitText() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(cleaned) else {
            text = display
            return
        }
        let bounded = max(0, min(parsed, 100_000))
        commit(bounded)
        text = Format.number(bounded)
    }
}
