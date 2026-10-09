import AVFoundation
import os

/// Beeps and speech over other audio (podcasts) with the mute switch on.
///
/// Session modes:
/// - `mix`: `.playback` + `.mixWithOthers` — podcast at full volume, beeps on top.
///   Active for the whole workout.
/// - `duck`: `.mixWithOthers` + `.duckOthers` — only while speaking an interval name;
///   iOS applies ducking on activation and lifts it on deactivation, so the session is
///   re-activated around each utterance. The duck level itself is fixed by the system.
///
/// While a workout is active a silent track loops so the app keeps running in the
/// background (`UIBackgroundModes: audio`) between beeps.
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
    private let log = Logger(subsystem: "me.rstm.Yoga", category: "audio")

    private let session = AVAudioSession.sharedInstance()
    private let synthesizer = AVSpeechSynthesizer()
    private var players: [Beep: AVAudioPlayer] = [:]
    private var silence: AVAudioPlayer?
    private var isWorkoutActive = false
    /// Utterances queued and not yet finished. `synthesizer.isSpeaking` is still `true`
    /// inside `didFinish`, so it cannot be used to decide when to lift the ducking.
    private var speaking = 0
    /// The mode the last `set` call asked for; pending retries bail out if it changed.
    private var target: Mode = .idle

    override init() {
        super.init()
        synthesizer.delegate = self

        // Players implicitly activate the session on first use; make sure that happens
        // with `.mixWithOthers`, otherwise opening the app pauses a running podcast.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])

        for beep in [Beep.short, .long] {
            guard let url = Bundle.main.url(forResource: beep.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else {
                assertionFailure("missing sound \(beep.rawValue)")
                continue
            }

            players[beep] = player
        }

        if let url = Bundle.main.url(forResource: "silence", withExtension: "wav"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = -1
            player.volume = 0
            silence = player
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
    }

    // MARK: Workout lifecycle

    func startWorkout() {
        isWorkoutActive = true
        set(.mix)
    }

    /// Ends the session; waits for the current speech (e.g. "Workout complete!") first.
    func endWorkout() {
        isWorkoutActive = false

        if speaking == 0 {
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
        speaking += 1
        set(.duck)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    // MARK: Session

    /// Switches the session mode. Deactivation fails while any of our audio is still
    /// running (e.g. right after speech ends), so it is retried a few times.
    private func set(_ mode: Mode, attempt: Int = 0) {
        target = mode

        guard mode != self.mode else { return }

        if self.mode != .idle {
            silence?.pause()

            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                log.notice("deactivated (\(String(describing: self.mode)) -> \(String(describing: mode)), attempt \(attempt))")
            } catch {
                log.error("deactivate failed (attempt \(attempt)): \(error)")

                guard attempt < 10 else {
                    log.error("giving up deactivation, forcing mode \(String(describing: mode))")
                    self.mode = .idle
                    set(mode)
                    return
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self, target == mode else { return }

                    set(mode, attempt: attempt + 1)
                }
                return
            }
        }

        self.mode = mode

        guard mode != .idle else { return }

        let options: AVAudioSession.CategoryOptions = mode == .duck
            ? [.mixWithOthers, .duckOthers]
            : [.mixWithOthers]

        do {
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
            silence?.play()
            log.notice("activated \(String(describing: mode)), options \(self.session.categoryOptions.rawValue), otherAudio \(self.session.isOtherAudioPlaying)")
        } catch {
            log.error("activate \(String(describing: mode)) failed: \(error)")
        }
    }

    /// Resumes the keep-alive track after a phone call or another interruption.
    @objc private func interruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended,
              mode != .idle
        else {
            return
        }

        try? session.setActive(true)
        silence?.play()
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            speaking = max(0, speaking - 1)
            log.notice("speech finished, still queued \(self.speaking)")

            guard speaking == 0 else { return }

            set(isWorkoutActive ? .mix : .idle)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        speechSynthesizer(synthesizer, didFinish: utterance)
    }
}
