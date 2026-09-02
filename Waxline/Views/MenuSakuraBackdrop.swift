import AVFoundation
import SwiftUI

@MainActor
@Observable
final class MenuIntroPlayback {
    let player = AVPlayer()
    private(set) var isReady = false
    private(set) var didFinish = false
    private(set) var progress = 0.0

    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var musicPlayer: AVQueuePlayer?
    @ObservationIgnored private var musicLooper: AVPlayerLooper?
    @ObservationIgnored private var videoFadeObserver: Any?
    @ObservationIgnored private var musicFadeObserver: Any?
    @ObservationIgnored private var menuVisible = false
    @ObservationIgnored private var soundEnabled = true

    init() {
        player.actionAtItemEnd = .pause
        player.isMuted = false
        player.volume = 0
        load()
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        applySoundState()
    }

    func setMenuVisible(_ visible: Bool) {
        menuVisible = visible
        if visible {
            resumeIfNeeded()
        } else {
            player.pause()
            musicPlayer?.pause()
        }
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "mainpagesakuravideo", withExtension: "mp4") else {
            didFinish = true
            progress = 1
            return
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)

        let music = AVQueuePlayer()
        music.volume = 0
        musicLooper = AVPlayerLooper(player: music, templateItem: AVPlayerItem(url: url))
        musicPlayer = music
        videoFadeObserver = attachFade(to: player)
        musicFadeObserver = attachFade(to: music)

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in
                self?.isReady = true
                let seconds = item.duration.seconds
                if seconds.isFinite, seconds > 0, self?.didFinish == false {
                    self?.progress = min(1, max(0, (self?.player.currentTime().seconds ?? 0) / seconds))
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.freezeAtEnd()
            }
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    private func applySoundState() {
        if soundEnabled {
            player.isMuted = didFinish
            if menuVisible {
                resumeIfNeeded()
            }
        } else {
            player.isMuted = true
            player.volume = 0
            musicPlayer?.volume = 0
            musicPlayer?.pause()
        }
    }

    private func resumeIfNeeded() {
        activateSession()
        if didFinish {
            if soundEnabled {
                musicPlayer?.play()
            } else {
                musicPlayer?.pause()
            }
        } else {
            player.isMuted = !soundEnabled
            player.play()
        }
    }

    private func attachFade(to player: AVPlayer) -> Any {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        return player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            guard let player, let item = player.currentItem else { return }
            let duration = item.duration.seconds
            let current = time.seconds
            guard duration.isFinite, duration > 0, current.isFinite else { return }
            let fade = Self.loopVolume(at: current, duration: duration)
            Task { @MainActor in
                guard let self else { return }
                player.volume = self.soundEnabled ? fade : 0
                if player === self.player, !self.didFinish {
                    self.progress = min(1, max(0, current / duration))
                }
            }
        }
    }

    nonisolated private static func loopVolume(at time: Double, duration: Double) -> Float {
        let fade = min(2.4, duration / 3)
        guard fade > 0.05 else { return 1 }
        let rising: Double
        if time < fade {
            rising = time / fade
        } else if time > duration - fade {
            rising = max(0, (duration - time) / fade)
        } else {
            rising = 1
        }
        let eased = rising * rising * (3 - 2 * rising)
        let floor: Double = 0.42
        return Float(floor + (1 - floor) * eased)
    }

    func skip() {
        guard !didFinish else { return }
        freezeAtEnd(seekToEnd: true)
    }

    private func freezeAtEnd(seekToEnd: Bool = true) {
        didFinish = true
        progress = 1
        player.pause()
        player.isMuted = true
        if seekToEnd, let duration = player.currentItem?.duration, duration.isValid, duration.isNumeric {
            player.seek(to: duration, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        activateSession()
        if soundEnabled {
            musicPlayer?.play()
        }
    }
}

struct MenuSakuraBackdrop: View {
    var playback: MenuIntroPlayback

    var body: some View {
        PlayerLayerView(player: playback.player)
            .opacity(playback.isReady ? 1 : 0)
            .background(Theme.cream)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.player = player
    }

    final class PlayerView: UIView {
        private let playerLayer = AVPlayerLayer()

        var player: AVPlayer? {
            get { playerLayer.player }
            set {
                playerLayer.player = newValue
                playerLayer.videoGravity = .resizeAspectFill
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            clipsToBounds = true
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
            playerLayer.videoGravity = .resizeAspectFill
        }
    }
}
