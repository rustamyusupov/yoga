import AVFoundation

/// Beeps and speech over other audio (podcasts) with the mute switch on.
///
/// Session modes:
/// - `mix`: `.playback` + `.mixWithOthers` — podcast at full volume, beeps on top.
///   Active for the whole workout.
/// - `duck`: `.mixWithOthers` + `.duckOthers` — only while speaking an interval name;
///   iOS applies ducking on activation and lifts it on deactivation, so the session is
///   re-activated around each utterance. The duck level itself is fixed by the system.
@MainActor
final class SoundPlayer: NSObject, AVSpeechSynthesizerDelegate {
    enum Beep: String {
        case short = "beep_short"
        case long = "beep_long"
    }

    enum Mode: Equatable {
        case idle, mix, duck
    }

    private(set) var mode: Mode = .idle

    private let session = AVAudioSession.sharedInstance()
    private let synthesizer = AVSpeechSynthesizer()
    private var players: [Beep: AVAudioPlayer] = [:]
    private var isWorkoutActive = false

    override init() {
        super.init()
        synthesizer.delegate = self

        for beep in [Beep.short, .long] {
            guard let url = Bundle.main.url(forResource: beep.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else {
                assertionFailure("missing sound \(beep.rawValue)")
                continue
            }

            player.prepareToPlay()
            players[beep] = player
        }
    }

    // MARK: Workout lifecycle

    func startWorkout() {
        isWorkoutActive = true
        set(.mix)
    }

    /// Ends the session; waits for the current speech (e.g. "Workout complete!") first.
    func endWorkout() {
        isWorkoutActive = false

        if !synthesizer.isSpeaking {
            set(.idle)
        }
    }

    // MARK: Sounds

    func play(_ beep: Beep) {
        guard let player = players[beep] else { return }

        if mode == .idle {
            set(.mix)
        }

        player.currentTime = 0
        player.play()
    }

    func speak(_ text: String) {
        set(.duck)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    // MARK: Session

    private func set(_ mode: Mode) {
        guard mode != self.mode else { return }

        do {
            if self.mode != .idle {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            }

            self.mode = mode

            guard mode != .idle else { return }

            let options: AVAudioSession.CategoryOptions = mode == .duck
                ? [.mixWithOthers, .duckOthers]
                : [.mixWithOthers]

            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            print("audio session \(mode):", error)
        }
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let stillSpeaking = synthesizer.isSpeaking

        Task { @MainActor in
            guard !stillSpeaking else { return }

            set(isWorkoutActive ? .mix : .idle)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechSynthesizer(synthesizer, didFinish: utterance)
    }
}
