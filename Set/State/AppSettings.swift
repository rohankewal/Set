import Foundation
import Observation
import SwiftUI

/// Appearance choice. `system` follows iOS; the other two pin the palette, which
/// matters in a gym where the phone's auto-brightness fights you.
enum ThemeMode: String, CaseIterable, Sendable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// App-level preferences. Small enough to live in `UserDefaults`, observable so
/// views stay in sync without passing bindings around.
@Observable
final class AppSettings {
    private enum Key {
        static let unit = "settings.weightUnit"
        static let theme = "settings.theme"
        static let barWeight = "settings.barWeightKg"
        static let defaultRest = "settings.defaultRestSeconds"
        static let autoRest = "settings.autoStartRest"
        static let haptics = "settings.haptics"
        static let restAlerts = "settings.restAlerts"
        static let keepAwake = "settings.keepAwake"
        static let requireBiometrics = "settings.requireBiometrics"
        static let selectedAthlete = "settings.selectedAthleteID"
        static let activeSession = "settings.activeSessionID"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.defaultRest: 90,
            Key.autoRest: true,
            Key.haptics: true,
            Key.restAlerts: true,
            Key.keepAwake: true,
            Key.requireBiometrics: false
        ])
        _unit = WeightUnit(rawValue: defaults.string(forKey: Key.unit) ?? "") ?? .kilograms
        _theme = ThemeMode(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        let storedBar = defaults.double(forKey: Key.barWeight)
        _barWeightKg = storedBar > 0 ? storedBar : 20
        _defaultRestSeconds = defaults.integer(forKey: Key.defaultRest)
        _autoStartRest = defaults.bool(forKey: Key.autoRest)
        _hapticsEnabled = defaults.bool(forKey: Key.haptics)
        _restAlertsEnabled = defaults.bool(forKey: Key.restAlerts)
        _keepScreenAwake = defaults.bool(forKey: Key.keepAwake)
        _requireBiometrics = defaults.bool(forKey: Key.requireBiometrics)
        _selectedAthleteID = defaults.string(forKey: Key.selectedAthlete).flatMap(UUID.init(uuidString:))
        _activeSessionID = defaults.string(forKey: Key.activeSession).flatMap(UUID.init(uuidString:))
    }

    @ObservationIgnored private var _unit: WeightUnit
    var unit: WeightUnit {
        get { access(keyPath: \.unit); return _unit }
        set { withMutation(keyPath: \.unit) { _unit = newValue; defaults.set(newValue.rawValue, forKey: Key.unit) } }
    }

    @ObservationIgnored private var _theme: ThemeMode
    var theme: ThemeMode {
        get { access(keyPath: \.theme); return _theme }
        set { withMutation(keyPath: \.theme) { _theme = newValue; defaults.set(newValue.rawValue, forKey: Key.theme) } }
    }

    /// Weight of the empty bar, in kilograms. Feeds the plate calculator and the
    /// warm-up ramp.
    @ObservationIgnored private var _barWeightKg: Double
    var barWeightKg: Double {
        get { access(keyPath: \.barWeightKg); return _barWeightKg }
        set {
            withMutation(keyPath: \.barWeightKg) {
                _barWeightKg = max(0, min(newValue, 100))
                defaults.set(_barWeightKg, forKey: Key.barWeight)
            }
        }
    }

    @ObservationIgnored private var _defaultRestSeconds: Int
    var defaultRestSeconds: Int {
        get { access(keyPath: \.defaultRestSeconds); return _defaultRestSeconds }
        set {
            withMutation(keyPath: \.defaultRestSeconds) {
                _defaultRestSeconds = min(max(newValue, 15), 600)
                defaults.set(_defaultRestSeconds, forKey: Key.defaultRest)
            }
        }
    }

    @ObservationIgnored private var _autoStartRest: Bool
    var autoStartRest: Bool {
        get { access(keyPath: \.autoStartRest); return _autoStartRest }
        set { withMutation(keyPath: \.autoStartRest) { _autoStartRest = newValue; defaults.set(newValue, forKey: Key.autoRest) } }
    }

    @ObservationIgnored private var _hapticsEnabled: Bool
    var hapticsEnabled: Bool {
        get { access(keyPath: \.hapticsEnabled); return _hapticsEnabled }
        set { withMutation(keyPath: \.hapticsEnabled) { _hapticsEnabled = newValue; defaults.set(newValue, forKey: Key.haptics) } }
    }

    @ObservationIgnored private var _restAlertsEnabled: Bool
    var restAlertsEnabled: Bool {
        get { access(keyPath: \.restAlertsEnabled); return _restAlertsEnabled }
        set { withMutation(keyPath: \.restAlertsEnabled) { _restAlertsEnabled = newValue; defaults.set(newValue, forKey: Key.restAlerts) } }
    }

    @ObservationIgnored private var _keepScreenAwake: Bool
    var keepScreenAwake: Bool {
        get { access(keyPath: \.keepScreenAwake); return _keepScreenAwake }
        set { withMutation(keyPath: \.keepScreenAwake) { _keepScreenAwake = newValue; defaults.set(newValue, forKey: Key.keepAwake) } }
    }

    @ObservationIgnored private var _requireBiometrics: Bool
    var requireBiometrics: Bool {
        get { access(keyPath: \.requireBiometrics); return _requireBiometrics }
        set { withMutation(keyPath: \.requireBiometrics) { _requireBiometrics = newValue; defaults.set(newValue, forKey: Key.requireBiometrics) } }
    }

    @ObservationIgnored private var _selectedAthleteID: UUID?
    var selectedAthleteID: UUID? {
        get { access(keyPath: \.selectedAthleteID); return _selectedAthleteID }
        set {
            withMutation(keyPath: \.selectedAthleteID) {
                _selectedAthleteID = newValue
                defaults.set(newValue?.uuidString, forKey: Key.selectedAthlete)
            }
        }
    }

    /// Lets an interrupted workout be picked back up after a cold launch.
    @ObservationIgnored private var _activeSessionID: UUID?
    var activeSessionID: UUID? {
        get { access(keyPath: \.activeSessionID); return _activeSessionID }
        set {
            withMutation(keyPath: \.activeSessionID) {
                _activeSessionID = newValue
                defaults.set(newValue?.uuidString, forKey: Key.activeSession)
            }
        }
    }
}
