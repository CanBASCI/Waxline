import SwiftUI

struct SheetActionButton: View {
    var title: String
    var prominent: Bool
    var enabled: Bool = true
    var action: () -> Void

    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.body, design: .serif).weight(prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? prominentLabel : secondaryLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(prominent ? prominentFill : secondaryFill, in: Capsule())
                .overlay {
                    Capsule().stroke(prominent ? Color.clear : secondaryStroke, lineWidth: 1)
                }
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var sheetDark: Bool { settings.sakuraLook != .color }

    private var prominentFill: Color {
        sheetDark ? Color.white.opacity(0.16) : Theme.waxRed
    }

    private var prominentLabel: Color {
        sheetDark ? Theme.ink(dark: true) : Theme.cream
    }

    private var secondaryFill: Color {
        sheetDark ? Color.white.opacity(0.08) : Theme.chipFill(dark: false)
    }

    private var secondaryLabel: Color {
        Theme.ink(dark: sheetDark)
    }

    private var secondaryStroke: Color {
        Theme.ink(dark: sheetDark).opacity(0.35)
    }
}

struct LeaveMatchConfirm: View {
    var onLeave: () -> Void
    var onCancel: () -> Void

    @Environment(SettingsStore.self) private var settings

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(t("gc_leave_title"))
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Text(t("gc_leave_message"))
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                SheetActionButton(title: t("gc_leave_confirm"), prominent: true, action: onLeave)
                SheetActionButton(title: t("gc_cancel"), prominent: false, action: onCancel)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}
