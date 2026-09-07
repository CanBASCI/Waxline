import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void
    @Environment(SettingsStore.self) private var settings
    @State private var page = 0

    private let pageCount = 4

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 4)

                pageBody
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    .highPriorityGesture(pageSwipe)

                Spacer(minLength: 4)

                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.28))
                            .frame(width: index == page ? 22 : 8, height: 8)
                    }
                }
                .padding(.bottom, 14)

                Button(action: advance) {
                    Text(page == pageCount - 1 ? t("onboarding_done") : t("onboarding_next"))
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .navigationTitle(t("menu_how_to_play"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.background)
        .preferredColorScheme(settings.sakuraLook.colorScheme)
        .animation(.easeOut(duration: 0.28), value: page)
    }

    private var pageBody: some View {
        VStack(spacing: 18) {
            pageArt(page)
            Text(t(copy(for: page)))
                .font(.system(.title3, design: .serif).weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var pageSwipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                if value.translation.width < -50 {
                    advance()
                } else if value.translation.width > 50, page > 0 {
                    page -= 1
                }
            }
    }

    private func advance() {
        if page >= pageCount - 1 {
            onDone()
            return
        }
        page += 1
    }

    private func copy(for index: Int) -> String.LocalizationValue {
        switch index {
        case 0: "onboarding_place"
        case 1: "onboarding_quadrant"
        case 2: "onboarding_rotate"
        default: "onboarding_five"
        }
    }

    @ViewBuilder
    private func pageArt(_ index: Int) -> some View {
        switch index {
        case 0:
            SealMark(
                color: Theme.waxBlack,
                motif: Theme.gold,
                outline: Theme.ink.opacity(0.2),
                outlineWidth: 1.2
            )
            .frame(width: 72, height: 72)
        case 1:
            tabletGrid(turned: false)
        case 2:
            tabletGrid(turned: true)
        default:
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { _ in
                    SealMark(
                        color: Theme.waxBlack,
                        motif: Theme.gold,
                        outline: Theme.ink.opacity(0.18),
                        outlineWidth: 1
                    )
                    .frame(width: 28, height: 28)
                }
            }
        }
    }

    private func tabletGrid(turned: Bool) -> some View {
        let gap: CGFloat = 8
        let side: CGFloat = 58
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                tabletTile(side: side, rotated: turned)
                tabletTile(side: side, rotated: false)
            }
            HStack(spacing: gap) {
                tabletTile(side: side, rotated: false)
                tabletTile(side: side, rotated: false)
            }
        }
    }

    private func tabletTile(side: CGFloat, rotated: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return charcoalImage
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipShape(shape)
            .overlay {
                shape.stroke(Theme.ink.opacity(rotated ? 0.35 : 0.12), lineWidth: rotated ? 1.2 : 0.8)
            }
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            .rotationEffect(.degrees(rotated ? 14 : 0))
    }

    private static let charcoalImage: Image = {
        if let image = PaperStyle.bundleImage("sakura_tablet_charcoal_color") {
            return Image(uiImage: image)
        }
        return Image(systemName: "square.fill")
    }()

    private var charcoalImage: Image { Self.charcoalImage }
}
