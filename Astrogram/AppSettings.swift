import Foundation

enum StartupLayer: Int {
    case none = 0
    case light = 1
    case clouds = 2
}

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let showLight = "showLightLayer"
        static let showClouds = "showCloudLayer"
        static let startupLayer = "startupLayer"
        static let nightMode = "nightMode"
    }

    var showLightLayer: Bool {
        get { defaults.object(forKey: Keys.showLight) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showLight) }
    }

    var showCloudLayer: Bool {
        get { defaults.object(forKey: Keys.showClouds) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.showClouds) }
    }

    var startupLayer: StartupLayer {
        get { StartupLayer(rawValue: defaults.integer(forKey: Keys.startupLayer)) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Keys.startupLayer) }
    }

    var nightMode: Bool {
        get { defaults.object(forKey: Keys.nightMode) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.nightMode) }
    }
}
