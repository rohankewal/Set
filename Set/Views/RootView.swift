import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine
    @Environment(AppLock.self) private var lock
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Athlete.createdAt) private var athletes: [Athlete]

    @State private var tab: AppTab = .today
    @State private var showingWorkout = false
    #if DEBUG
    @State private var showingSettingsForDebug = false
    @State private var showingRoutinesForDebug = false
    @State private var showingPlatesForDebug = false
    @State private var showingFocusForDebug = false
    #endif

    enum AppTab: Hashable { case today, history, progress, library }

    #if DEBUG
    /// `--screen progress` etc., so a specific screen can be inspected directly.
    private func applyDebugScreen() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--screen"),
              arguments.count > index + 1 else { return }
        switch arguments[index + 1] {
        case "settings": showingSettingsForDebug = true
        case "routines": showingRoutinesForDebug = true
        case "plates": showingPlatesForDebug = true
        case "dupes-make": DemoData.injectSyncDuplicates(context: context)
        case "dupes-fix": DemoData.verifyDeduplication(context: context)
        case "focus":
            if !engine.isRunning {
                engine.start(for: athlete)
                let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
                for name in ["Back Squat", "Bench Press"] {
                    if let exercise = library.first(where: { $0.name == name }),
                       let block = engine.addExercise(exercise),
                       let set = block.orderedSets.first {
                        set.weightKg = name == "Back Squat" ? 120 : 80
                        set.reps = 5
                    }
                }
            }
            showingFocusForDebug = true
        case "routinestart":
            if let routine = athlete?.allRoutines.first, !engine.isRunning {
                engine.start(routine: routine, for: athlete)
            }
            showingWorkout = true
        case "history": tab = .history
        case "progress": tab = .progress
        case "library": tab = .library
        case "workout":
            if !engine.isRunning {
                engine.start(for: athlete)
                let names = ["Back Squat", "Lateral Raise", "Face Pull"]
                let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
                var added: [ExerciseBlock] = []
                for name in names {
                    if let exercise = library.first(where: { $0.name == name }),
                       let block = engine.addExercise(exercise) {
                        added.append(block)
                    }
                }
                if let squat = added.first {
                    squat.orderedSets.first?.weightKg = 120
                    squat.orderedSets.first?.reps = 5
                    engine.addWarmupSets(to: squat)
                }
                if added.count >= 3 {
                    engine.groupSuperset([added[1], added[2]])
                }
            }
            showingWorkout = true
        case "summary":
            // Drives a whole workout through the engine, so the finish path and
            // milestone detection can be exercised without tapping.
            engine.start(for: athlete)
            let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            for (name, weight, reps) in [("Back Squat", 130.0, 5), ("Bench Press", 95.0, 6)] {
                guard let exercise = library.first(where: { $0.name == name }),
                      let block = engine.addExercise(exercise),
                      let set = block.orderedSets.first else { continue }
                set.weightKg = weight
                set.reps = reps
                engine.toggleCompletion(of: set, in: block)
            }
            engine.finish()
        case "rest":
            if !engine.isRunning {
                engine.start(for: athlete)
                let library = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
                if let exercise = library.first(where: { $0.name == "Back Squat" }),
                   let block = engine.addExercise(exercise),
                   let set = block.orderedSets.first {
                    set.weightKg = 120
                    set.reps = 5
                    engine.toggleCompletion(of: set, in: block)
                }
            }
            showingWorkout = true
        default: tab = .today
        }
    }
    #endif

    private var athlete: Athlete? {
        athletes.first { $0.id == settings.selectedAthleteID } ?? athletes.first
    }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                Tab("Today", systemImage: "circle.hexagongrid", value: AppTab.today) {
                    TodayView(athlete: athlete, showingWorkout: $showingWorkout)
                }
                Tab("History", systemImage: "list.bullet.indent", value: AppTab.history) {
                    HistoryView(athlete: athlete)
                }
                Tab("Progress", systemImage: "chart.bar", value: AppTab.progress) {
                    ProgressOverview(athlete: athlete)
                }
                Tab("Library", systemImage: "square.grid.2x2", value: AppTab.library) {
                    LibraryView()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory(isEnabled: engine.isRunning) {
                LiveWorkoutBar { showingWorkout = true }
            }

            if lock.isLocked {
                LockScreen()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .tint(Ink.primary)
        .sheet(isPresented: $showingWorkout) {
            ActiveWorkoutView(athlete: athlete)
        }
        #if DEBUG
        .sheet(isPresented: $showingSettingsForDebug) { SettingsView() }
        .sheet(isPresented: $showingPlatesForDebug) { PlateCalculatorView(totalKg: 142.5) }
        .fullScreenCover(isPresented: $showingFocusForDebug) {
            if let session = engine.session {
                FocusModeView(session: session, athlete: athlete)
            }
        }
        .sheet(isPresented: $showingRoutinesForDebug) {
            RoutinesView(athlete: athlete) { routine in
                engine.start(routine: routine, for: athlete)
                showingWorkout = true
            }
        }
        #endif
        .sheet(item: Binding(
            get: { engine.finishedSession },
            set: { engine.finishedSession = $0 }
        )) { session in
            SessionSummaryView(session: session)
        }
        .task {
            Seed.bootstrap(context)
            // Sync may have landed a second copy of the seeded library while the
            // app was closed. The full sweep runs here, once.
            Deduplicator.run(in: context, deep: true)
            await StoreHealth.shared.refreshSyncStatus()
            #if DEBUG
            DemoData.installIfRequested(context: context, settings: settings)
            applyDebugScreen()
            #endif
            if settings.selectedAthleteID == nil { settings.selectedAthleteID = athletes.first?.id }
            engine.restoreIfNeeded()
            if lock.isLocked { await lock.unlock() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.lockIfNeeded() }
            if phase == .active {
                Deduplicator.run(in: context)
                Task { await StoreHealth.shared.refreshSyncStatus() }
            }
        }
        .animation(Motion.gentle, value: lock.isLocked)
    }
}

/// Sheet helper for optional model objects, which `sheet(item:)` can't take
/// directly because `PersistentModel` isn't `Identifiable` in the way it wants.
private struct IdentifiedSession: Identifiable {
    let id: UUID
    let session: WorkoutSession
}

private extension View {
    func sheet(
        item: Binding<WorkoutSession?>,
        @ViewBuilder content: @escaping (WorkoutSession) -> some View
    ) -> some View {
        let wrapped = Binding<IdentifiedSession?>(
            get: { item.wrappedValue.map { IdentifiedSession(id: $0.id, session: $0) } },
            set: { item.wrappedValue = $0?.session }
        )
        return sheet(item: wrapped) { content($0.session) }
    }
}

// MARK: - Bottom accessory

/// Lives above the tab bar while a workout is in progress: elapsed time, or the
/// rest countdown when one is running. Tapping returns to the workout.
struct LiveWorkoutBar: View {
    @Environment(WorkoutEngine.self) private var engine
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                if engine.isRestActive {
                    RestRing(progress: engine.restProgress, size: 22)
                        .opacity(engine.isRestPaused ? 0.5 : 1)
                } else {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Ink.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(barLabel)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ink.tertiary)
                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        Text(barValue)
                            .font(.readout(17, weight: .semibold))
                            .foregroundStyle(Ink.primary)
                            .contentTransition(.numericText(countsDown: engine.isRestActive))
                    }
                }

                Spacer(minLength: 0)

                Text("\(engine.session?.completedSets.count ?? 0) sets")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var barLabel: String {
        if engine.isRestPaused { return "Rest paused" }
        if engine.isResting { return "Resting" }
        return engine.session?.title ?? "Workout"
    }

    private var barValue: String {
        if engine.isRestActive { return Format.clock(engine.restRemaining) }
        guard let started = engine.session?.startedAt else { return "0:00" }
        return Format.clock(Date.now.timeIntervalSince(started))
    }
}

// MARK: - Lock screen

struct LockScreen: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "lock")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Ink.primary)
                Text("Set is locked")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Ink.primary)
                Button("Unlock with \(lock.biometryLabel)") {
                    Task { await lock.unlock() }
                }
                .buttonStyle(QuietButtonStyle())
                if let error = lock.lastError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
    }
}

// MARK: - External display

/// iOS 27 scene accessory: a pared-back rest clock for a connected display.
struct ExternalRestDisplay: View {
    @Environment(WorkoutEngine.self) private var engine

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                VStack(spacing: 14) {
                    Text(engine.isResting ? "REST" : "SET")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(6)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(value)
                        .font(.system(size: 140, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: engine.isResting))
                }
            }
        }
    }

    private var value: String {
        if engine.isResting { return Format.clock(engine.restRemaining) }
        guard let started = engine.session?.startedAt else { return "—" }
        return Format.clock(Date.now.timeIntervalSince(started))
    }
}
