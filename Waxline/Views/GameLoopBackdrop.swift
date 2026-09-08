import AVFoundation
import SwiftUI

struct GameLoopBackdrop: View {
    var resource: String
    var ext: String = "mp4"

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                FillPlayerView(player: player)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear(perform: start)
        .onDisappear(perform: stop)
    }

    private func start() {
        guard player == nil else {
            player?.play()
            return
        }
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else { return }
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
        queue.play()
    }

    private func stop() {
        player?.pause()
    }
}

private struct FillPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> FillPlayerUIView {
        let view = FillPlayerUIView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: FillPlayerUIView, context: Context) {
        uiView.player = player
    }

    final class FillPlayerUIView: UIView {
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
            isUserInteractionEnabled = false
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
