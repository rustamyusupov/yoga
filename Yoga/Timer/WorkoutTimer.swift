import Foundation
import Observation

struct WorkoutSummary: Equatable, Sendable {
    let startedAt: Date
    let elapsed: Int
    let timers: [Interval]
}

/// Port of `timer.js`. Counts by wall-clock `Date`, not by ticks, so it catches up
/// after being suspended. Each interval lasts `time + 1` seconds: it shows `00:00`
/// for one second (long beep) before moving on — same as the web app.
@MainActor
@Observable
final class WorkoutTimer {
    enum Event: Equatable {
        /// The workout has started (first toggle).
        case run
        /// A new interval has started.
        case start(String)
        /// Remaining seconds changed.
        case tick(Int)
        /// The current interval reached zero.
        case end
        /// All intervals are done, state is already reset.
        case complete(WorkoutSummary)
    }

    typealias Handler = @MainActor (Event) -> Void

    private(set) var timers: [Interval]
    private(set) var isRunning = false
    private(set) var seconds = 0
    private(set) var index = 0
    private(set) var startedAt: Date?

    var activeIndex: Int? { seconds > 0 || isRunning ? index : nil }
    var current: Interval? { timers.indices.contains(index) ? timers[index] : nil }

    @ObservationIgnored private var lastTime: Date?
    @ObservationIgnored private var ticker: Ticker?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let makeTicker: TickerFactory
    @ObservationIgnored var onEvent: Handler

    init(
        timers: [Interval],
        now: @escaping () -> Date = Date.init,
        ticker: @escaping TickerFactory = Ticker.scheduled,
        onEvent: @escaping Handler = { _ in }
    ) {
        self.timers = timers
        self.now = now
        self.makeTicker = ticker
        self.onEvent = onEvent
    }

    // MARK: Actions

    func toggle() {
        guard let current else { return }

        if !isRunning, seconds == 0 {
            startedAt = now()
            onEvent(.run)
            onEvent(.start(current.name))
        }

        isRunning.toggle()

        if isRunning {
            if seconds == 0 {
                seconds = current.time
            }
            start()
        } else {
            stop()
        }
    }

    func reset() {
        isRunning = false
        seconds = 0
        index = 0
        lastTime = nil
        startedAt = nil
        ticker?.cancel()
        ticker = nil
    }

    func next() {
        index += 1

        guard let current else {
            finish()
            return
        }

        seconds = current.time
        onEvent(.start(current.name))
    }

    // MARK: Clock

    private func start() {
        lastTime = now()
        ticker?.cancel()
        ticker = makeTicker { [weak self] in
            self?.tick()
        }
    }

    private func stop() {
        ticker?.cancel()
        ticker = nil
        lastTime = nil
    }

    /// Advances the countdown by the whole seconds elapsed since the last tick.
    /// Unlike the web version the fractional remainder is kept, so the timer
    /// does not drift; a long gap (e.g. after suspension) walks through intervals.
    func tick() {
        guard isRunning, let lastTime else { return }

        let date = now()
        var elapsed = Int(date.timeIntervalSince(lastTime))

        guard elapsed >= 1 else { return }

        self.lastTime = lastTime.addingTimeInterval(TimeInterval(elapsed))

        while elapsed > 0 {
            let step = min(elapsed, seconds + 1)
            let before = seconds
            seconds -= step
            elapsed -= step
            onEvent(.tick(seconds))

            if before > 0, seconds <= 0 {
                onEvent(.end)
            }

            if seconds < 0 {
                next()

                if !isRunning {
                    return
                }
            }
        }
    }

    private func finish() {
        let summary = WorkoutSummary(
            startedAt: startedAt ?? now(),
            elapsed: Int((now().timeIntervalSince(startedAt ?? now())).rounded()),
            timers: timers
        )

        reset()
        onEvent(.complete(summary))
    }
}

// MARK: - Ticker

typealias TickerFactory = @MainActor (@escaping @MainActor () -> Void) -> Ticker

/// Repeating 100 ms callback on the main run loop, cancellable.
@MainActor
final class Ticker {
    private var timer: Timer?

    private init(timer: Timer?) {
        self.timer = timer
    }

    static func scheduled(_ body: @escaping @MainActor () -> Void) -> Ticker {
        let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated(body)
        }
        RunLoop.main.add(timer, forMode: .common)

        return Ticker(timer: timer)
    }

    /// A ticker that never fires on its own; the owner calls `tick()` manually.
    static func manual(_ body: @escaping @MainActor () -> Void) -> Ticker {
        Ticker(timer: nil)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
