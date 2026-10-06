import Foundation

enum SettingsStore {
    private static let key = "app.settings"

    static func load(defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return .default
        }
        do {
            var settings = try JSONDecoder().decode(AppSettings.self, from: data)
            settings.clamp()
            return settings
        } catch {
            return .default
        }
    }

    static func save(_ settings: AppSettings, defaults: UserDefaults = .standard) {
        var copy = settings
        copy.clamp()
        guard let data = try? JSONEncoder().encode(copy) else { return }
        defaults.set(data, forKey: key)
    }
}
