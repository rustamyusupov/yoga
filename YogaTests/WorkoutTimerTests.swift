import Foundation
import Testing
@testable import Yoga

/// Controllable wall clock for the timer.
@MainActor
private final class Clock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)

    func advance(_ seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

@MainActor
@Suite("WorkoutTimer")
struct WorkoutTimerTests {
    private let clock = Clock()
    private var events: [WorkoutTimer.Event] = []

    private func make(_ times: [Int], names: [String]? = nil) -> (WorkoutTimer, Events) {
        let events = Events()
        let timers = times.enumerated().map { index, time in
            Interval(id: index, name: names?[index] ?? "timer \(index)", time: time)
        }
        let timer = WorkoutTimer(timers: timers, now: { [clock] in clock.date }, ticker: Ticker.manual) {
            events.list.append($0)
        }

        return (timer, events)
    }

    /// Advances the clock in 100 ms steps, ticking the timer each step — like the real ticker.
    private func run(_ timer: WorkoutTimer, seconds: TimeInterval) {
        let steps = Int((seconds * 10).rounded())

        for _ in 0 ..< steps {
            clock.advance(0.1)
            timer.tick()
        }
    }

    @Test("starts idle")
    func idle() {
        let (timer, _) = make([30, 60])

        #expect(!timer.isRunning)
        #expect(timer.seconds == 0)
        #expect(timer.index == 0)
        #expect(timer.activeIndex == nil)
    }

    @Test("toggle starts the first interval")
    func toggleStarts() {
        let (timer, events) = make([5], names: ["test timer"])

        timer.toggle()

        #expect(timer.isRunning)
        #expect(timer.seconds == 5)
        #expect(timer.activeIndex == 0)
        #expect(timer.startedAt == clock.date)
        #expect(events.list == [.run, .start("test timer")])
    }

    @Test("toggle pauses and resumes without losing time")
    func togglePauses() {
        let (timer, _) = make([10])

        timer.toggle()
        run(timer, seconds: 2)
        #expect(timer.seconds == 8)

        timer.toggle()
        #expect(!timer.isRunning)
        run(timer, seconds: 3)
        #expect(timer.seconds == 8)

        timer.toggle()
        #expect(timer.isRunning)
        run(timer, seconds: 1)
        #expect(timer.seconds == 7)
    }

    @Test("moves to the next interval after time + 1 seconds")
    func movesToNext() {
        let (timer, events) = make([2, 3], names: ["first", "second"])

        timer.toggle()
        run(timer, seconds: 3)

        #expect(timer.index == 1)
        #expect(timer.seconds == 3)
        #expect(timer.activeIndex == 1)
        #expect(events.list == [.run, .start("first"), .tick(1), .tick(0), .end, .tick(-1), .start("second")])
    }

    @Test("ticks 3-2-1 and ends at zero")
    func ticks() {
        let (timer, events) = make([4])

        timer.toggle()
        run(timer, seconds: 4)

        #expect(events.list.filter { $0 != .run } == [.start("timer 0"), .tick(3), .tick(2), .tick(1), .tick(0), .end])
    }

    @Test("resets when all intervals complete and reports a summary")
    func completes() {
        let (timer, events) = make([1, 1], names: ["first", "second"])
        let startedAt = clock.date

        timer.toggle()
        run(timer, seconds: 4) // 1, 0, 1, 0

        #expect(!timer.isRunning)
        #expect(timer.seconds == 0)
        #expect(timer.index == 0)
        #expect(timer.activeIndex == nil)
        #expect(timer.startedAt == nil)

        let summary = WorkoutSummary(
            startedAt: startedAt,
            elapsed: 4,
            timers: [Interval(id: 0, name: "first", time: 1), Interval(id: 1, name: "second", time: 1)]
        )
        #expect(events.list.last == .complete(summary))
    }

    @Test("reset stops and clears state")
    func reset() {
        let (timer, _) = make([10])

        timer.toggle()
        run(timer, seconds: 2)
        timer.reset()

        #expect(!timer.isRunning)
        #expect(timer.seconds == 0)
        #expect(timer.index == 0)
        #expect(timer.activeIndex == nil)

        run(timer, seconds: 2)
        #expect(timer.seconds == 0)
    }

    @Test("next skips to the following interval")
    func next() {
        let (timer, events) = make([10, 5], names: ["first", "second"])

        timer.toggle()
        timer.next()

        #expect(timer.index == 1)
        #expect(timer.seconds == 5)
        #expect(events.list.last == .start("second"))
    }

    @Test("does not drift: fractional seconds are kept between ticks")
    func noDrift() {
        let (timer, _) = make([100])

        timer.toggle()
        // 100 ms ticks over 30 s: the web version would lose up to 10 %
        run(timer, seconds: 30)

        #expect(timer.seconds == 70)
    }

    @Test("catches up after a long gap across several intervals")
    func catchUp() {
        let (timer, events) = make([5, 5, 5], names: ["a", "b", "c"])

        timer.toggle()
        clock.advance(13) // a: 6 s, b: 6 s, c: 1 s elapsed
        timer.tick()

        #expect(timer.index == 2)
        #expect(timer.seconds == 4)
        #expect(events.list.filter { if case .start = $0 { true } else { false } } == [.start("a"), .start("b"), .start("c")])
        #expect(events.list.filter { $0 == .end }.count == 2)
    }

    @Test("catching up past the end completes the workout once")
    func catchUpToEnd() {
        let (timer, events) = make([1, 1])

        timer.toggle()
        clock.advance(60)
        timer.tick()

        #expect(!timer.isRunning)
        #expect(events.list.filter { if case .complete = $0 { true } else { false } }.count == 1)
    }

    @Test("toggle on an empty workout does nothing")
    func empty() {
        let (timer, events) = make([])

        timer.toggle()

        #expect(!timer.isRunning)
        #expect(events.list.isEmpty)
    }
}

@MainActor
private final class Events {
    var list: [WorkoutTimer.Event] = []
}
