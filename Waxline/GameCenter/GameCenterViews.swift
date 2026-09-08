import GameKit
import SwiftUI
import UIKit

struct GameCenterAuthPresenter: UIViewControllerRepresentable {
    var viewController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if uiViewController.presentedViewController == nil {
            uiViewController.present(viewController, animated: true)
        }
    }
}

struct GameCenterInviteList: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(GameCenterService.self) private var gameCenter
    var onSelect: (GameCenterInvite) -> Void
    var onNewMatch: () -> Void

    private func t(_ key: String.LocalizationValue) -> String {
        L10n.text(key, language: settings.language)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(gameCenter.pendingInvites) { invite in
                        Button {
                            onSelect(invite)
                        } label: {
                            InviteSenderRow(invite: invite, invitedYou: t("gc_invitation"))
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { gameCenter.deletePendingInvites(at: $0) }
                } footer: {
                    if gameCenter.pendingInvites.isEmpty {
                        Text(t("gc_no_invites"))
                    }
                }
                Section {
                    Button(t("gc_new_match"), action: onNewMatch)
                }
            }
            .navigationTitle(t("gc_invites"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await gameCenter.refreshPendingInvites()
            }
        }
        .presentationDetents([.medium])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .presentationBackground(.background)
        .preferredColorScheme(settings.sakuraLook.colorScheme)
    }
}

private struct InviteSenderRow: View {
    var invite: GameCenterInvite
    var invitedYou: String
    @State private var photo: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.opponentName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(invitedYou)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .task(id: invite.id) {
            photo = await invite.loadPhoto()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
        }
    }
}

