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

enum PresetLibraryStore {
    private static let key = "app.presets"

    static func load(defaults: UserDefaults = .standard) -> PresetLibrary {
        guard let data = defaults.data(forKey: key) else {
            return .empty
        }
        do {
            var library = try JSONDecoder().decode(PresetLibrary.self, from: data)
            library.clamp()
            return library
        } catch {
            return .empty
        }
    }

    static func save(_ library: PresetLibrary, defaults: UserDefaults = .standard) {
        var copy = library
        copy.clamp()
        guard let data = try? JSONEncoder().encode(copy) else { return }
        defaults.set(data, forKey: key)
    }
}
