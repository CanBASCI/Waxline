import AVFoundation
import Testing
@testable import Waxline

struct MenuIntroMediaTests {
    @Test func lastVisibleTimeIsOneFrameBeforeEnd() {
        let duration = CMTime(seconds: 15.041667, preferredTimescale: 12_288)
        let last = MenuIntroMedia.lastVisibleTime(
            duration: duration,
            frameDuration: CMTime(value: 1, timescale: 24)
        )
        #expect(last.isNumeric)
        #expect(last.seconds > 14.9)
        #expect(last.seconds < duration.seconds)
    }

    @Test func lastVisibleTimeRejectsInvalidDuration() {
        #expect(MenuIntroMedia.lastVisibleTime(duration: .invalid) == .zero)
        #expect(MenuIntroMedia.lastVisibleTime(duration: .zero) == .zero)
    }

    @Test func loopVolumeFadesAtEdgesAndPeaksInTheMiddle() {
        #expect(MenuIntroMedia.loopVolume(at: 0, duration: 15) < 0.5)
        #expect(MenuIntroMedia.loopVolume(at: 7.5, duration: 15) == 1)
        #expect(MenuIntroMedia.loopVolume(at: 15, duration: 15) < 0.5)
    }

    @Test func audioOnlyCompositionKeepsAudioAndDropsVideo() async throws {
        let bundle = Bundle(for: MenuIntroPlayback.self)
        guard let url = bundle.url(forResource: "mainpagesakuravideo", withExtension: "mp4") else {
            Issue.record("mainpagesakuravideo.mp4 is not in the app bundle")
            return
        }
        let composition = try await MenuIntroMedia.audioOnlyComposition(from: AVURLAsset(url: url))
        let audio = try await composition.loadTracks(withMediaType: .audio)
        let video = try await composition.loadTracks(withMediaType: .video)
        #expect(!audio.isEmpty)
        #expect(video.isEmpty)
    }
}
