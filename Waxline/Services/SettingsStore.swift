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
    var sakuraLook: SakuraLook {
        didSet { UserDefaults.standard.set(sakuraLook.rawValue, forKey: Keys.sakuraLook) }
    }

    init() {
        let defaults = UserDefaults.standard
        soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        aiLevel = AILevel(rawValue: defaults.string(forKey: Keys.ai) ?? "") ?? .medium
        language = LanguageOverride(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .system
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        sakuraLook = SakuraLook(rawValue: defaults.string(forKey: Keys.sakuraLook) ?? "") ?? .mono
    }

    private enum Keys {
        static let sound = "waxline.sound"
        static let haptics = "waxline.haptics"
        static let ai = "waxline.ai"
        static let language = "waxline.language"
        static let onboarding = "waxline.onboarding"
        static let sakuraLook = "waxline.sakuraLook"
    }
}

enum DeviceLanguage: Sendable {
    nonisolated static let catalogCodes = ["en", "tr", "de", "es", "ja"]

    nonisolated static var locale: Locale {
        Locale(identifier: primaryIdentifier)
    }

    nonisolated static var primaryIdentifier: String {
        preferredIdentifiers.first ?? "en"
    }

    nonisolated static var catalogCode: String {
        for identifier in preferredIdentifiers {
            let lower = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
            if let match = catalogCodes.first(where: { lower == $0 || lower.hasPrefix($0 + "-") }) {
                return match
            }
            if let code = Locale(identifier: identifier).language.languageCode?.identifier.lowercased(),
               catalogCodes.contains(code) {
                return code
            }
        }
        return "en"
    }

    nonisolated static var preferredIdentifiers: [String] {
        if let languages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String],
           !languages.isEmpty {
            return languages
        }
        return Locale.preferredLanguages
    }

    nonisolated static func clearAppLanguageOverride() {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    }
}

enum L10n: Sendable {
    nonisolated static func text(_ key: String.LocalizationValue, language: LanguageOverride) -> String {
        String(
            localized: key,
            bundle: bundle(for: language),
            locale: language.locale ?? DeviceLanguage.locale
        )
    }

    nonisolated static func system(_ key: String.LocalizationValue) -> String {
        text(key, language: .system)
    }

    nonisolated private static func bundle(for language: LanguageOverride) -> Bundle {
        let code = language.catalogCode ?? DeviceLanguage.catalogCode
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}
