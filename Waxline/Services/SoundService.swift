import AudioToolbox

enum SoundService {
    static func place(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(1104)
    }

    static func rotate(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(1057)
    }

    static func win(enabled: Bool) {
        guard enabled else { return }
        AudioServicesPlaySystemSound(1025)
    }
}
