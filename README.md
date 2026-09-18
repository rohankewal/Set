# Set

A minimal, monochrome iOS workout tracker: sets, reps, and milestones. Built with
SwiftUI + SwiftData for iOS 27.

## What it does

- **Log a workout** — start a session, add movements, log weight × reps (or reps /
  time for bodyweight and isometric work). Every new set prefills from your last
  one, so a normal set is one tap.
- **Rest dial** — the bottom of the workout is one control with three states:
  a slim bar with a play button when idle, and a large ring that drains, breathes
  while it runs, and pauses/resumes on a single big tap once a rest starts. ±15s
  and skip sit under it, plus an optional local notification so the phone can go
  in a pocket. Completing a working set starts it automatically.
- **Milestones** — heaviest set, best estimated 1RM (Epley), rep records, session
  volume records, workout-count badges, week streaks and lifetime tonnage are
  detected as they happen and shown as a banner mid-set, then recapped on the
  finish summary.
- **History & progress** — sessions grouped by month, 8-week volume chart,
  strongest lifts, and a per-exercise estimated-max trend.
- **People** — one athlete, named "You" until you change it in Settings › Your
  name. A coach can add a person per client and switch from the header; each
  keeps separate history and records.
- **270-movement library** — barbell, dumbbell, machine, cable, Smith, kettlebell,
  band, sled, med ball and bodyweight work across chest, back, shoulders, arms,
  legs, glutes, core, full-body/Olympic and cardio, each tagged with how it's
  measured (weight × reps, reps, or time). Anything missing is one tap to create.
- **Appearance** — System, Light or Dark, chosen from palette swatches rather
  than a list of words.
- **Routines** — save a finished workout as a routine in one tap, or build one by
  hand; starting it pre-fills the exercises, sets and target reps, with weights
  carried over from your history.
- **Set types** — working, warm-up, drop, to-failure and AMRAP, each counted
  correctly: warm-ups never touch volume, drop sets never claim a heaviest-set
  record, AMRAP sets are where rep records come from. Optional RPE per set.
- **Supersets** — pair adjacent exercises; they share a rule down the side, get
  A1/A2 tags, and the rest timer only fires after the last one in the group.
- **Warm-up ramp** — one tap builds 40/55/70/85% sets below your working weight,
  rounded to loadable plates and floored at the empty bar.
- **Plate calculator** — what to hang on each side, drawn to scale rather than
  listed, with a configurable bar weight.
- **Next-set suggestion** — a tappable hint based on last time: another rep, or a
  step up in load once you clear the rep target. It fills the set; it never
  programs for you.
- **Body weight** — one reading a day, charted alongside the lifting.
- **Consistency grid** — 17 weeks of training as one block of marks, weekday
  aligned.
- **Sets per muscle** — weekly hard sets by muscle group, which is what
  programmes are actually written in.

- **Focus mode** — one exercise on screen at a time, palm-sized log button, swipe
  between exercises, full-screen rest clock. For the phone on the bench, gloves on.
- **The read** — session density, actual-vs-planned rest, stall detection and a
  deload flag, all computed in Swift. On Apple Intelligence devices the on-device
  model rewrites the sentence; every number stays the app's own.
- **Live Activity** — the rest countdown on the Lock Screen and in the Dynamic
  Island, with what's coming next.
- **Widgets** — *This Week* (small, medium, large: sessions, week marks, 8-week
  volume, the consistency grid), *Last Workout* (small, medium: the last session,
  or a live timer while one is running, with Start/Resume), and *Streak* on the
  Lock Screen. They read a snapshot the app writes to the App Group, never the
  store, and show only a lock when Face ID is on.
- **Apple Watch** — the current set and one button to log it, plus rest controls.
  The phone owns the data; the watch is a remote control.

## Design

Black, white and five greys, defined once in `Shared/Theme.swift` and resolved
dynamically so light and dark are true inversions. One accent: an inverted fill.
Hairline dividers, wide-tracked micro-labels, monospaced numerals with tight
optical tracking. No colour coding, no illustrations, no confetti.

## Architecture

```
App/      SetApp.swift          — container, environment wiring, scene accessory
Shared/   RestActivity.swift    — Live Activity contract (app + widget)
          WatchLink.swift       — phone/watch wire format (app + watch)
          WidgetSnapshot.swift  — what widgets read, via the App Group
          Theme.swift           — palette, type, motion (every target)
          Units.swift           — kg-native storage, kg/lb presentation
SetTimer/ RestLiveActivity      — Lock Screen and Dynamic Island
          HomeWidgets           — home screen and Lock Screen widgets
SetWatch/ WatchRootView         — the watch app
Model/    StoreSchema.swift     — versioned schema + migration plan
          Deduplicator.swift    — merges what sync duplicated
          Models.swift          — SwiftData: Athlete, Exercise, WorkoutSession,
                                   ExerciseBlock, SetRecord, Milestone,
                                   Routine, RoutineItem, BodyEntry
          PlateMath.swift       — barbell loading, plate rounding
          Stats.swift           — bests, weekly volume, streaks, milestone engine
          Seed.swift            — starter movement library (idempotent)
          Export.swift          — JSON archive and CSV via Transferable
          Insights.swift        — density, rest adherence, stalls, the read
          DemoData.swift        — DEBUG-only fixtures
State/    WorkoutEngine.swift   — the live session: mutations, rest clock, awards
          AppSettings.swift     — @Observable UserDefaults preferences
          AppLock.swift         — optional Face ID / passcode gate
          Haptics / RestAlerts  — feedback, local notifications
          CoachNarrator.swift   — Apple Intelligence rewrite, grounded + optional
          StoreHealth.swift     — save/sync reporting behind the warnings
          LiveActivityController / PhoneWatchLink
          WidgetPublisher.swift — writes the widget snapshot on change
Design/   Components            — buttons, cards, rings
Views/    one file per surface
```

Data flows one way: views render SwiftData models and call `WorkoutEngine` for
anything that mutates a live workout, which keeps set logging, PR detection and
the rest clock in a single testable place.

## iOS 27 features used

- `reorderContainer(for:move:)` + `ForEach.reorderable()` — drag to reorder
  exercises directly in the workout stack (not a `List`, no edit mode).
- `ToolbarItemPlacement.topBarPinnedTrailing` — **Finish** stays reachable as the
  toolbar collapses; `visibilityPriority(.low)` drops the overflow menu first.
- `navigationTransition(.crossFade)` on detail pushes.
- `sceneAccessory { ExternalNonInteractiveAccessory { … } }` — mirrors the rest
  clock to a connected external display (guarded to iOS; the API is unavailable
  on macOS, Catalyst and visionOS).
- Liquid Glass rest control, `tabViewBottomAccessory(isEnabled:)` live-workout
  bar, and `tabBarMinimizeBehavior(.onScrollDown)`.

## Apple Intelligence, used honestly

`Insights` computes every number in Swift. `CoachNarrator` then asks the
on-device `SystemLanguageModel` to rewrite *one claim the app already decided on*,
giving it only the facts behind that claim. Three things follow:

- The computed read renders immediately, so nobody waits on a model.
- A rewrite that mentions a number absent from those facts is discarded
  (`isGrounded`), so the model cannot introduce a statistic.
- On devices without Apple Intelligence the feature is simply the Swift version.
  Nothing is gated behind it, and "show the working" lists the facts either way.

Nothing is sent anywhere: `SystemLanguageModel` runs on the device.

## Sync

The store syncs through the user's **own private CloudKit database** — there is
no server of ours, no account to create beyond the iCloud one they already have,
and nothing shared with anyone. A second device, or a replacement phone, picks up
the same log.

CloudKit imposes three rules that shaped the model layer:

- **No unique constraints.** The nine `#Unique` macros are gone; identity is
  enforced by `Deduplicator` instead, which merges by name for library movements
  and athletes (the case that really happens: two devices each seed their own
  copy of the 270-movement library) and by id for everything else. It runs on
  launch and on foreground, repointing history onto the surviving record so no
  logged set is ever orphaned.
- **Every to-many relationship must be optional.** The stored properties follow
  that; `allSessions`, `allBlocks`, `allSets` and friends keep call sites clean.
- **Every relationship needs an inverse.** `Exercise` gained `blocks` and
  `routineItems`, both `.nullify`, so deleting a movement can't take history with it.

**Before any release that changes the model**, bring CloudKit's Production schema
up to date: run a Debug build once with `--init-cloudkit-schema` on a device or
simulator signed into iCloud (it creates every record type and field in
Development, where normal use would miss some), then *Deploy Schema Changes* in
the CloudKit Console. Production schema changes are additive only — fields can't
be removed or retyped afterwards.

Sync state is reported plainly in Settings ("Syncing with iCloud", "Not signed in
to iCloud"); when it isn't working, the log still writes locally and nothing is
lost.

## Privacy & security

- No server, no analytics, no account of ours. Data lives on device and in the
  user's private iCloud database.
- Optional Face ID / Touch ID / passcode gate (`LocalAuthentication`), re-locking
  whenever the app leaves the foreground.
- App Sandbox on, user-selected files read-only.
- Export is user-initiated (CSV or JSON), goes through the share sheet, and
  contains only what was entered.
- A store that won't open never fails silently: the app falls back to memory and
  says so on Today and in Settings, rather than looking empty.

## Platforms

iPhone and iPad (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`). The UI is
built on iPhone-only SwiftUI — bottom tab bar with accessory, `topBar*` toolbar
placements, numeric keypads — so the target is deliberately not built for native
macOS or visionOS.

## Running

```sh
xcodebuild -project Set.xcodeproj -scheme Set \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Debug-only launch arguments for reviewing screens with content:

```
--demo                 seed ~8 weeks of training for one athlete
--screen today|history|progress|library|settings|routines|routinestart|
        workout|rest|focus|plates|summary|dupes-make|dupes-fix
```

`--demo` **replaces** the athletes in the store, so point it at a simulator, not
a device you actually train with.
