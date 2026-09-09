import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void
    @Environment(SettingsStore.self) private var settings
    @State private var page = 0
    @State private var goingForward = true

    private let pageCount = 5

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 4)

                ZStack {
                    pageBody
                        .id(page)
                        .transition(.asymmetric(
                            insertion: .move(edge: goingForward ? .trailing : .leading)
                                .combined(with: .opacity),
                            removal: .move(edge: goingForward ? .leading : .trailing)
                                .combined(with: .opacity)
                        ))
                }
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

                SheetActionButton(
                    title: page == pageCount - 1 ? t("onboarding_done") : t("onboarding_next"),
                    prominent: true,
                    action: advance
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .navigationTitle(t("menu_how_to_play"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.background)
        .preferredColorScheme(settings.sakuraLook.colorScheme)
    }

    private var pageBody: some View {
        VStack(spacing: 18) {
            pageArt(page)
            VStack(spacing: 10) {
                Text(t(headline(for: page)))
                    .font(.system(.title3, design: .serif).weight(.medium))
                    .foregroundStyle(.primary)
                Text(t(detail(for: page)))
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
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
                    show(page - 1)
                }
            }
    }

    private func advance() {
        if page >= pageCount - 1 {
            onDone()
            return
        }
        show(page + 1)
    }

    private func show(_ newPage: Int) {
        goingForward = newPage > page
        withAnimation(.easeOut(duration: 0.28)) {
            page = newPage
        }
    }

    private func headline(for index: Int) -> String.LocalizationValue {
        switch index {
        case 0: "onboarding_place"
        case 1: "onboarding_quadrant"
        case 2: "onboarding_rotate"
        case 3: "onboarding_five"
        default: "onboarding_invite"
        }
    }

    private func detail(for index: Int) -> String.LocalizationValue {
        switch index {
        case 0: "onboarding_place_detail"
        case 1: "onboarding_quadrant_detail"
        case 2: "onboarding_rotate_detail"
        case 3: "onboarding_five_detail"
        default: "onboarding_invite_detail"
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
        case 3:
            VStack(spacing: 12) {
                scoreSample(count: 5, points: 1, sealSize: 22)
                scoreSample(count: 6, points: 2, sealSize: 20)
            }
        default:
            HStack(spacing: 16) {
                SealMark(
                    color: Theme.waxCinnabar,
                    motif: Theme.gold,
                    outline: Theme.ink.opacity(0.18),
                    outlineWidth: 1.1
                )
                .frame(width: 56, height: 56)
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                SealMark(
                    color: Theme.waxDusk,
                    motif: Theme.gold,
                    outline: Theme.ink.opacity(0.18),
                    outlineWidth: 1
                )
                .frame(width: 40, height: 40)
                .opacity(0.55)
            }
        }
    }

    private func scoreSample(count: Int, points: Int, sealSize: CGFloat) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { _ in
                    SealMark(
                        color: Theme.waxBlack,
                        motif: Theme.gold,
                        outline: Theme.ink.opacity(0.16),
                        outlineWidth: 1
                    )
                    .frame(width: sealSize, height: sealSize)
                }
            }
            Text("+\(points)")
                .font(.system(.headline, design: .serif).weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
