import SwiftData
import SwiftUI

@main
struct SetApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings
    @State private var engine: WorkoutEngine
    @State private var lock: AppLock
    @State private var watchLink = PhoneWatchLink()

    init() {
        let schema = Schema([
            Athlete.self,
            Exercise.self,
            WorkoutSession.self,
            ExerciseBlock.self,
            SetRecord.self,
            Milestone.self,
            Routine.self,
            RoutineItem.self,
            BodyEntry.self
        ])
        // Synced through the user's own private CloudKit database: no server of
        // ours, no account to create, and it's what makes a second device — or a
        // replacement phone — pick up the same log.
        //
        // The store lives in the App Group container. SwiftData puts it there on
        // its own once an App Group entitlement exists; saying so explicitly means
        // adding or removing a group later can't silently move it and strand the
        // log in the old location.
        var configuration = ModelConfiguration(
            "SetStore",
            schema: schema,
            groupContainer: .identifier(WidgetStore.appGroup),
            cloudKitDatabase: .automatic
        )
        #if DEBUG
        if CloudKitSchema.isRequested {
            // This launch only pushes the schema. The real store stays off
            // CloudKit meanwhile, so the placeholder records the schema pass
            // uploads can never be imported into it.
            configuration = ModelConfiguration(
                "SetStore",
                schema: schema,
                groupContainer: .identifier(WidgetStore.appGroup),
                cloudKitDatabase: .none
            )
            CloudKitSchema.initializeInBackground()
        }
        #endif
        let container: ModelContainer
        var fallbackReason: String?
        do {
            container = try ModelContainer(
                for: schema,
                migrationPlan: SetMigrationPlan.self,
                configurations: configuration
            )
        } catch {
            // A store that won't open must not brick the app: run from memory so
            // the user can still train. This is a data-loss state, so it is shown
            // on Today and in Settings rather than quietly logged.
            fallbackReason = (error as NSError).localizedDescription
            // Explicitly local: if the store failed *because* CloudKit rejected
            // something, a fallback that also talks to CloudKit fails the same
            // way — and a crash here would be the worst possible outcome.
            container = try! ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
            )
        }
        self.container = container
        if let fallbackReason {
            MainActor.assumeIsolated {
                StoreHealth.shared.reportMemoryFallback(reason: fallbackReason)
            }
        }

        let settings = AppSettings()
        Haptics.enabled = settings.hapticsEnabled
        let engine = WorkoutEngine(context: container.mainContext, settings: settings)
        let watchLink = PhoneWatchLink()
        watchLink.engine = engine
        engine.watch = watchLink
        watchLink.activate(settings: settings)

        _settings = State(initialValue: settings)
        _engine = State(initialValue: engine)
        _watchLink = State(initialValue: watchLink)
        _lock = State(initialValue: AppLock(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(engine)
                .environment(lock)
                .modelContainer(container)
                .preferredColorScheme(settings.theme.colorScheme)
                .restMirror(engine: engine)
        }
    }
}

private extension View {
    /// iOS 27 only: mirrors the rest clock to a connected external display, so a
    /// phone propped on a bench can be read from across the rack. The scene
    /// accessory API doesn't exist on macOS, Catalyst or visionOS, where the app
    /// simply runs without it.
    @ViewBuilder
    func restMirror(engine: WorkoutEngine) -> some View {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        sceneAccessory {
            ExternalNonInteractiveAccessory {
                ExternalRestDisplay()
                    .environment(engine)
            }
        }
        #else
        self
        #endif
    }
}
