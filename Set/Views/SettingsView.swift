import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppLock.self) private var lock
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var confirmErase = false
    @Query(sort: \Athlete.createdAt) private var athletes: [Athlete]
    @FocusState private var nameFocused: Bool

    private var athlete: Athlete? {
        athletes.first { $0.id == settings.selectedAthleteID } ?? athletes.first
    }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        profileSection
                        appearanceSection
                        unitsSection
                        restSection
                        feedbackSection
                        privacySection
                        dataSection
                        aboutSection
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, 10)
                    .padding(.bottom, 50)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold))
                }
            }
            .confirmationDialog(
                "Erase every workout, milestone and custom movement?",
                isPresented: $confirmErase,
                titleVisibility: .visible
            ) {
                Button("Erase everything", role: .destructive) { erase() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: Sections

    /// The one piece of identity in the app. Starts as "You" and is a single tap
    /// away from being your actual name.
    @ViewBuilder
    private var profileSection: some View {
        if let athlete {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Your name") {
                    if athletes.count > 1 {
                        Text("\(athletes.count) athletes")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Ink.secondary)
                    }
                }
                HStack(spacing: 12) {
                    Text(athlete.initials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Ink.onAccent)
                        .frame(width: 40, height: 40)
                        .background(Ink.accent, in: .circle)

                    TextField("Your name", text: Binding(
                        get: { athlete.name },
                        set: { athlete.rename($0) }
                    ))
                    .focused($nameFocused)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Ink.primary)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { commitName() }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                .background(Ink.surface, in: .rect(cornerRadius: Metric.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                        .strokeBorder(nameFocused ? Ink.primary.opacity(0.45) : Ink.line, lineWidth: Metric.hairline)
                }
                .animation(Motion.tick, value: nameFocused)
            }
        }
    }

    private func commitName() {
        guard let athlete else { return }
        let trimmed = athlete.name.trimmingCharacters(in: .whitespaces)
        athlete.rename(trimmed.isEmpty ? "You" : trimmed)
        context.saveChanges()
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Appearance")
            HStack(spacing: 10) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Button {
                        settings.theme = mode
                        Haptics.play(.tick)
                    } label: {
                        ThemeSwatch(mode: mode, isSelected: settings.theme == mode)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(Motion.snap, value: settings.theme)
        }
    }

    private var unitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Units")
            Picker("Weight unit", selection: Binding(
                get: { settings.unit },
                set: { settings.unit = $0 }
            )) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            Text("Stored in kilograms and converted for display, so switching never rewrites your history.")
                .font(.system(size: 12))
                .foregroundStyle(Ink.tertiary)

            Card(padding: 0) {
                HStack {
                    Text("Bar weight").font(.rowTitle).foregroundStyle(Ink.primary)
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { settings.barWeightKg },
                            set: { settings.barWeightKg = $0 }
                        ),
                        in: 0...100,
                        step: settings.unit == .kilograms ? 2.5 : 2.26796
                    ) { EmptyView() }
                    .labelsHidden()
                    Text("\(Format.weight(settings.barWeightKg, in: settings.unit)) \(settings.unit.short)")
                        .font(.rowValue)
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 74, alignment: .trailing)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Rest")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Default rest").font(.rowTitle).foregroundStyle(Ink.primary)
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { settings.defaultRestSeconds },
                                set: { settings.defaultRestSeconds = $0 }
                            ),
                            in: 15...600,
                            step: 15
                        ) {
                            Text(restLabel)
                                .font(.rowValue)
                                .foregroundStyle(Ink.secondary)
                        }
                        .labelsHidden()
                        Text(restLabel)
                            .font(.rowValue)
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                    Hairline(inset: 18)
                    toggleRow("Start timer automatically", isOn: Binding(
                        get: { settings.autoStartRest },
                        set: { settings.autoStartRest = $0 }
                    ))
                    Hairline(inset: 18)
                    toggleRow("Alert when rest ends", isOn: Binding(
                        get: { settings.restAlertsEnabled },
                        set: { settings.restAlertsEnabled = $0 }
                    ))
                }
            }
        }
    }

    private var restLabel: String {
        let seconds = settings.defaultRestSeconds
        return seconds < 60 ? "\(seconds)s" : (seconds % 60 == 0 ? "\(seconds / 60)m" : "\(seconds / 60)m \(seconds % 60)s")
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Feel")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    toggleRow("Haptics", isOn: Binding(
                        get: { settings.hapticsEnabled },
                        set: { settings.hapticsEnabled = $0; Haptics.enabled = $0 }
                    ))
                    Hairline(inset: 18)
                    toggleRow("Keep screen awake while training", isOn: Binding(
                        get: { settings.keepScreenAwake },
                        set: { settings.keepScreenAwake = $0 }
                    ))
                }
            }
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Privacy")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    toggleRow("Require \(lock.biometryLabel)", isOn: Binding(
                        get: { settings.requireBiometrics },
                        set: { settings.requireBiometrics = $0; lock.refreshRequirement() }
                    ))
                    .disabled(!lock.isAvailable)
                }
            }
            Text("Your log syncs through your own private iCloud database — there's no account to create and no server of ours involved. Nothing is shared, and there's no analytics. Locking adds a check every time the app returns to the foreground.")
                .font(.system(size: 12))
                .foregroundStyle(Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Data")

            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Storage").font(.rowTitle).foregroundStyle(Ink.primary)
                        Spacer()
                        Text(StoreHealth.shared.isHealthy ? "On this device" : "Attention")
                            .font(.rowValue)
                            .foregroundStyle(Ink.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: StoreHealth.shared.sync.isWorking ? "icloud" : "icloud.slash")
                            .font(.system(size: 11, weight: .medium))
                        Text(StoreHealth.shared.sync.label)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Ink.tertiary)
                    if let warning = StoreHealth.shared.warning {
                        Text(warning)
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let detail = StoreHealth.shared.detail {
                            Text(detail)
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(Ink.tertiary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    } else if let saved = StoreHealth.shared.lastSavedAt {
                        Text("Last write \(saved.formatted(.relative(presentation: .numeric)))")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.tertiary)
                    } else {
                        Text("Saved locally as you log. No account, no sync.")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.tertiary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
            }
            ShareLink(
                item: TrainingCSV.build(from: context, unit: settings.unit),
                preview: SharePreview("Set export (CSV)")
            ) {
                exportRow("Export as CSV", caption: "One row per set")
            }

            ShareLink(item: TrainingArchive.build(from: context), preview: SharePreview("Set export")) {
                exportRow("Export as JSON", caption: "Full structure, for backup")
            }

            Button("Erase all data", role: .destructive) { confirmErase = true }
                .buttonStyle(InkButtonStyle(prominent: false, height: 50))
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("About")
            Text("Set \(Bundle.main.shortVersion)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.secondary)
            Text("Sets, reps, milestones. Nothing else.")
                .font(.system(size: 13))
                .foregroundStyle(Ink.tertiary)
        }
    }

    private func exportRow(_ title: String, caption: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(caption).font(.system(size: 12)).foregroundStyle(Ink.tertiary)
            }
            Spacer()
            Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(Ink.primary)
        .padding(.horizontal, 18)
        .frame(height: 60)
        .background(Ink.surface, in: .rect(cornerRadius: Metric.controlRadius + 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metric.controlRadius + 2, style: .continuous)
                .strokeBorder(Ink.line, lineWidth: Metric.hairline)
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title).font(.rowTitle).foregroundStyle(Ink.primary)
        }
        .toggleStyle(SwitchToggleStyle(tint: Ink.accent))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func erase() {
        for athlete in (try? context.fetch(FetchDescriptor<Athlete>())) ?? [] {
            context.delete(athlete)
        }
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] where exercise.isCustom {
            context.delete(exercise)
        }
        context.saveChanges()
        settings.activeSessionID = nil
        settings.selectedAthleteID = nil
        Seed.bootstrap(context)
        dismiss()
    }
}

extension Bundle {
    var shortVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
}

/// Appearance tile: a miniature of the palette it selects, so the choice is
/// visible rather than described.
private struct ThemeSwatch: View {
    let mode: ThemeMode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(preview)
                    .frame(height: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Ink.line, lineWidth: Metric.hairline)
                    }
                Image(systemName: mode.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(glyph)
            }
            Text(mode.label)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Ink.primary : Ink.tertiary)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Ink.primary : Color.clear, lineWidth: 1.5)
        }
        .contentShape(.rect)
    }

    private var preview: AnyShapeStyle {
        switch mode {
        case .system:
            AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.5),
                        .init(color: Color(white: 0.06), location: 0.5)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .light: AnyShapeStyle(Color.white)
        case .dark: AnyShapeStyle(Color(white: 0.06))
        }
    }

    private var glyph: Color {
        switch mode {
        case .system: .gray
        case .light: Color(white: 0.1)
        case .dark: Color(white: 0.95)
        }
    }
}
