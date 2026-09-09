import SwiftUI

struct MoreApp: Identifiable {
    var id: String { storeURL.absoluteString }
    var name: String
    var iconResource: String
    var subtitleKey: String.LocalizationValue
    var storeURL: URL
}

enum MoreAppsCatalog {
    static let apps: [MoreApp] = [
        MoreApp(
            name: "Coffee Atlas - My Journey",
            iconResource: "coffee_atlas_icon",
            subtitleKey: "more_apps_coffee_subtitle",
            storeURL: URL(string: "https://apps.apple.com/tr/app/coffee-atlas-my-journey/id6757154434")!
        ),
        MoreApp(
            name: "Eventime - Hub",
            iconResource: "eventime_hub_icon",
            subtitleKey: "more_apps_eventime_subtitle",
            storeURL: URL(string: "https://apps.apple.com/tr/app/eventime-hub/id6743343288")!
        )
    ]
}

struct MoreAppsSheet: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        NavigationStack {
            List(MoreAppsCatalog.apps) { app in
                Button {
                    openURL(app.storeURL)
                } label: {
                    MoreAppRow(app: app, subtitle: t(app.subtitleKey))
                }
                .buttonStyle(.plain)
            }
            .font(.system(.body, design: .serif))
            .navigationTitle(t("more_apps_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.background)
        .preferredColorScheme(settings.sakuraLook.colorScheme)
    }
}

private struct MoreAppRow: View {
    var app: MoreApp
    var subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(.body, design: .serif).weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "icloud.and.arrow.down")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color(uiColor: .systemBlue))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), \(subtitle)")
    }

    private var icon: some View {
        let shape = RoundedRectangle(cornerRadius: 13.4, style: .continuous)
        return Group {
            if let image = PaperStyle.bundleImage(app.iconResource) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(width: 60, height: 60)
        .background(Color.secondary.opacity(0.12))
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
