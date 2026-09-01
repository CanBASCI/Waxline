import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void
    @Environment(SettingsStore.self) private var settings
    @State private var page = 0

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    private var pages: [(String.LocalizationValue, String)] {
        [
            ("onboarding_place", "hand.tap"),
            ("onboarding_quadrant", "square.split.2x2"),
            ("onboarding_rotate", "arrow.clockwise"),
            ("onboarding_five", "star.fill")
        ]
    }

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Spacer()
                Button(t("onboarding_skip"), action: onDone)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()
            Image(systemName: pages[page].1)
                .font(.system(size: 64))
                .foregroundStyle(Theme.waxRed)
            Text(t(pages[page].0))
                .font(.system(.title2, design: .serif))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Theme.waxRed : Theme.ink.opacity(0.2))
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }

            Button(page == pages.count - 1 ? t("onboarding_done") : t("onboarding_next")) {
                if page == pages.count - 1 {
                    onDone()
                } else {
                    page += 1
                }
            }
            .buttonStyle(WaxButtonStyle(fill: Theme.waxRed))
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .background(Theme.cream.ignoresSafeArea())
    }
}
