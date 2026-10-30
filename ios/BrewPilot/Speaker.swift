import AVFoundation

/// Voice coach: hands are on the kettle and eyes on the bed, so cues are
/// spoken. Playback category so the ring/silent switch doesn't mute it.
/// Between cues nothing plays, so the side buttons move the ringer, not
/// this; `volume` (Scale tab slider) is the in-app control.
@MainActor
final class Speaker {
    var enabled = true
    var volume: Float = 0.6

    private let synth = AVSpeechSynthesizer()
    private var configured = false

    func say(_ text: String, interrupt: Bool = false) {
        guard enabled, !text.isEmpty else { return }
        if !configured {
            configured = true
            let audio = AVAudioSession.sharedInstance()
            try? audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? audio.setActive(true)
        }
        if interrupt { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = volume
        synth.speak(utterance)
    }
}
