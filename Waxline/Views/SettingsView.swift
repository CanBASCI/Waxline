import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    private var menuFont: Font { .system(.body, design: .serif).weight(.medium) }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Toggle(t("settings_sound"), isOn: $settings.soundEnabled)
                    Toggle(t("settings_haptics"), isOn: $settings.hapticsEnabled)
                }
                Section(t("settings_ai")) {
                    Picker(t("settings_ai"), selection: $settings.aiLevel) {
                        Text(t("ai_easy")).tag(AILevel.easy)
                        Text(t("ai_medium")).tag(AILevel.medium)
                        Text(t("ai_hard")).tag(AILevel.hard)
                    }
                    .pickerStyle(.segmented)
                }
                Section(t("settings_language")) {
                    Picker(t("settings_language"), selection: $settings.language) {
                        Text(t("language_system")).tag(LanguageOverride.system)
                        Text(t("language_english")).tag(LanguageOverride.english)
                        Text(t("language_turkish")).tag(LanguageOverride.turkish)
                    }
                }
            }
            .font(menuFont)
            .contentMargins(.top, 14, for: .scrollContent)
            .navigationTitle(t("settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(t("settings_title"))
                        .font(menuFont)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("done")) { dismiss() }
                        .font(menuFont)
                }
            }
        }
    }
}
