/// Maps timer events to sounds — the `createTimer` callbacks from the web app.
@MainActor
struct WorkoutSounds {
    let player: SoundPlayer

    func handle(_ event: WorkoutTimer.Event) {
        switch event {
        case .run:
            player.startWorkout()
        case .start(let name):
            player.speak(name)
        case .tick(let seconds) where (1 ... 3).contains(seconds):
            player.play(.short)
        case .tick:
            break
        case .end:
            player.play(.long)
        case .complete:
            player.speak("Workout complete!")
            player.endWorkout()
        }
    }
}
