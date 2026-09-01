import Foundation
import Observation

@Observable
final class SettingsStore {
    var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Keys.sound) }
    }
    var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    var aiLevel: AILevel {
        didSet { UserDefaults.standard.set(aiLevel.rawValue, forKey: Keys.ai) }
    }
    var language: LanguageOverride {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }
    var boardDark: Bool {
        didSet { UserDefaults.standard.set(boardDark, forKey: Keys.boardDark) }
    }
    var sealPalette: SealPalette {
        didSet { UserDefaults.standard.set(sealPalette.rawValue, forKey: Keys.sealPalette) }
    }
    var tableFinish: TableFinish {
        didSet { UserDefaults.standard.set(tableFinish.rawValue, forKey: Keys.tableFinish) }
    }
    var tabletFinish: TabletFinish {
        didSet { UserDefaults.standard.set(tabletFinish.rawValue, forKey: Keys.tabletFinish) }
    }

    init() {
        let defaults = UserDefaults.standard
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        aiLevel = AILevel(rawValue: defaults.string(forKey: Keys.ai) ?? "") ?? .medium
        language = LanguageOverride(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        boardDark = defaults.bool(forKey: Keys.boardDark)
        sealPalette = SealPalette(rawValue: defaults.string(forKey: Keys.sealPalette) ?? "") ?? .classic
        tableFinish = TableFinish(rawValue: defaults.string(forKey: Keys.tableFinish) ?? "") ?? .walnut
        tabletFinish = TabletFinish(rawValue: defaults.string(forKey: Keys.tabletFinish) ?? "") ?? .granite
    }

    private enum Keys {
        static let sound = "waxline.sound"
        static let haptics = "waxline.haptics"
        static let ai = "waxline.ai"
        static let language = "waxline.language"
        static let onboarding = "waxline.onboarding"
        static let boardDark = "waxline.boardDark"
        static let sealPalette = "waxline.sealPalette"
        static let tableFinish = "waxline.tableFinish"
        static let tabletFinish = "waxline.tabletFinish"
    }
}

enum L10n {
    static func text(_ key: String.LocalizationValue, language: LanguageOverride) -> String {
        if let locale = language.locale {
            return String(localized: key, locale: locale)
        }
        return String(localized: key)
    }
}
