import AudioRouting
import Foundation

/// Persists `Settings` as JSON in a fixed defaults domain, so a `swift run` build and the
/// bundled app share the same preferences.
@MainActor
final class SettingsStore {
    private static let key = "settings"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppInfo.bundleIdentifier)) {
        self.defaults = defaults ?? .standard
    }

    func load() -> Settings {
        guard let data = defaults.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return decoded
    }

    func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
