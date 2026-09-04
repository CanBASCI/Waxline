import AVFoundation
import SwiftUI

enum MenuIntroMediaError: Error {
    case missingAudioTrack
}

enum MenuIntroMedia {
    /// Last seconds of the intro: loop plays underneath and opacity crossfades.
    /// Long enough to read as continuity, short enough to avoid a double-image.
    static let visualHandoffDuration: Double = 2.0
    /// Decode the loop a moment before the fade so the first visible frame is ready.
    static let visualHandoffPreroll: Double = 0.25

    static func lastVisibleTime(
        duration: CMTime,
        frameDuration: CMTime = CMTime(value: 1, timescale: 24)
    ) -> CMTime {
        guard duration.isValid, duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else {
            return .zero
        }
        let last = CMTimeSubtract(duration, frameDuration)
        return last.isNumeric && last.seconds > 0 ? last : .zero
    }

    nonisolated static func loopVolume(at time: Double, duration: Double) -> Float {
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

    static func audioOnlyComposition(from asset: AVAsset) async throws -> AVMutableComposition {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw MenuIntroMediaError.missingAudioTrack
        }
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        for track in audioTracks {
            guard let dest = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            try dest.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        }
        return composition
    }
}

@MainActor
@Observable
final class MenuIntroPlayback {
    let player = AVPlayer()
    let loopPlayer = AVQueuePlayer()
    private(set) var isReady = false
    private(set) var didFinish = false
    private(set) var progress = 0.0
    /// 0 = intro only, 1 = loop only. Driven by remaining intro time, not a scale animation.
    private(set) var handoff = 0.0

    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var musicPlayer: AVQueuePlayer?
    @ObservationIgnored private var musicLooper: AVPlayerLooper?
    @ObservationIgnored private var videoFadeObserver: Any?
    @ObservationIgnored private var musicFadeObserver: Any?
    @ObservationIgnored private var loopLooper: AVPlayerLooper?
    @ObservationIgnored private var menuVisible = false
    @ObservationIgnored private var soundEnabled = true
    @ObservationIgnored private var loopHandoffStarted = false
    @ObservationIgnored private var handoffTask: Task<Void, Never>?

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
            loopPlayer.pause()
        }
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "mainpagesakuravideo", withExtension: "mp4") else {
            didFinish = true
            progress = 1
            handoff = 1
            loopHandoffStarted = true
            prepareVisualLoop()
            return
        }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .pause

        videoFadeObserver = attachFade(to: player)

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            Task { @MainActor in
                self?.markReadyAfterFirstFrame()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.freezeAtEnd(seekToLastFrame: false)
            }
        }

        Task { await prepareAudioLoop(from: asset) }
        prepareVisualLoop()
    }

    private func markReadyAfterFirstFrame() {
        guard !isReady else { return }
        player.preroll(atRate: 1) { [weak self] _ in
            Task { @MainActor in
                self?.finishReady()
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            self.finishReady()
        }
    }

    private func finishReady() {
        guard !isReady else { return }
        isReady = true
        let seconds = player.currentItem?.duration.seconds ?? 0
        if seconds.isFinite, seconds > 0, !didFinish {
            progress = min(1, max(0, player.currentTime().seconds / seconds))
        }
        if menuVisible {
            resumeIfNeeded()
        }
    }

    private func prepareVisualLoop() {
        loopPlayer.isMuted = true
        loopPlayer.volume = 0
        guard let url = Bundle.main.url(forResource: "gamescreensakuravideo", withExtension: "mov") else { return }
        loopLooper = AVPlayerLooper(player: loopPlayer, templateItem: AVPlayerItem(url: url))
    }

    private func prepareAudioLoop(from asset: AVAsset) async {
        do {
            let audioOnly = try await MenuIntroMedia.audioOnlyComposition(from: asset)

            let music = AVQueuePlayer()
            music.volume = 0
            music.actionAtItemEnd = .advance
            let template = AVPlayerItem(asset: audioOnly)
            musicLooper = AVPlayerLooper(player: music, templateItem: template)
            musicPlayer = music
            musicFadeObserver = attachFade(to: music)
            startMusicIfNeeded()
        } catch {
            return
        }
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        let mode: AVAudioSession.Mode = didFinish ? .default : .moviePlayback
        try? session.setCategory(.playback, mode: mode)
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
            player.pause()
            player.rate = 0
            player.isMuted = true
            startMusicIfNeeded()
            startVisualLoopIfNeeded()
        } else {
            player.isMuted = !soundEnabled
            player.play()
            if loopHandoffStarted {
                startVisualLoopIfNeeded()
            } else {
                loopPlayer.pause()
            }
        }
    }

    private func startVisualLoopIfNeeded() {
        guard menuVisible, didFinish || loopHandoffStarted else {
            loopPlayer.pause()
            return
        }
        loopPlayer.isMuted = true
        loopPlayer.volume = 0
        loopPlayer.play()
    }

    private func startMusicIfNeeded() {
        guard didFinish, menuVisible else {
            musicPlayer?.pause()
            return
        }
        if soundEnabled {
            musicPlayer?.play()
        } else {
            musicPlayer?.pause()
        }
    }

    private func attachFade(to player: AVPlayer) -> Any {
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        return player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self, weak player] time in
            guard let player, let item = player.currentItem else { return }
            let duration = item.duration.seconds
            let current = time.seconds
            guard duration.isFinite, duration > 0, current.isFinite else { return }
            let fade = MenuIntroMedia.loopVolume(at: current, duration: duration)
            Task { @MainActor in
                guard let self else { return }
                player.volume = self.soundEnabled ? fade : 0
                if player === self.player, !self.didFinish {
                    self.progress = min(1, max(0, current / duration))
                    self.updateVisualHandoff(current: current, duration: duration)
                }
            }
        }
    }

    func skip() {
        guard !didFinish else { return }
        freezeAtEnd(seekToLastFrame: true)
    }

    private func updateVisualHandoff(current: Double, duration: Double) {
        let remaining = duration - current
        let window = MenuIntroMedia.visualHandoffDuration
        let preroll = MenuIntroMedia.visualHandoffPreroll
        if remaining <= window + preroll {
            beginLoopHandoff()
        }
        guard remaining <= window else { return }
        let raw = min(1, max(0, 1 - remaining / window))
        handoff = raw * raw * (3 - 2 * raw)
    }

    private func beginLoopHandoff() {
        guard !loopHandoffStarted else { return }
        loopHandoffStarted = true
        startVisualLoopIfNeeded()
    }

    private func setHandoff(_ value: Double, animated: Bool) {
        handoffTask?.cancel()
        let target = min(1, max(0, value))
        guard animated, abs(target - handoff) > 0.02 else {
            handoff = target
            return
        }
        let from = handoff
        handoffTask = Task { @MainActor in
            let duration = 0.55
            let start = Date()
            while !Task.isCancelled {
                let u = Date().timeIntervalSince(start) / duration
                if u >= 1 {
                    handoff = target
                    break
                }
                let t = u * u * (3 - 2 * u)
                handoff = from + (target - from) * t
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func freezeAtEnd(seekToLastFrame: Bool) {
        let alreadyFinished = didFinish
        didFinish = true
        progress = 1
        player.pause()
        player.rate = 0
        player.isMuted = true
        if let videoFadeObserver {
            player.removeTimeObserver(videoFadeObserver)
            self.videoFadeObserver = nil
        }
        if seekToLastFrame, !alreadyFinished, let duration = player.currentItem?.duration, duration.isValid, duration.isNumeric {
            let time = MenuIntroMedia.lastVisibleTime(duration: duration)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    self?.player.pause()
                    self?.player.rate = 0
                }
            }
        }
        beginLoopHandoff()
        setHandoff(1, animated: seekToLastFrame && handoff < 0.95)
        activateSession()
        startMusicIfNeeded()
        startVisualLoopIfNeeded()
    }
}

struct MenuSakuraBackdrop: View {
    var playback: MenuIntroPlayback

    var body: some View {
        ZStack {
            Theme.cream
            PlayerLayerView(player: playback.player)
                .opacity(playback.isReady ? 1 - playback.handoff : 0)
            PlayerLayerView(player: playback.loopPlayer)
                .opacity(playback.handoff)
        }
        .clipped()
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
