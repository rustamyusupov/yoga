import Foundation
import Testing
@testable import Yoga

private func parse(_ json: String) throws -> Workout {
    try WorkoutParser.parse(Data(json.utf8))
}

@Suite("WorkoutParser")
struct WorkoutParserTests {
    @Test("keeps name and sport from a workout object")
    func fullObject() throws {
        let workout = try parse(
            #"{ "name": "Yoga", "sport": "Yoga", "timers": [{ "id": 0, "name": "Cat-Cow", "time": 90 }] }"#
        )

        #expect(workout == Workout(name: "Yoga", sport: "Yoga", timers: [Interval(id: 0, name: "Cat-Cow", time: 90)]))
    }

    @Test("wraps a plain timers array with default name and sport")
    func bareArray() throws {
        let workout = try parse(#"[{ "id": 0, "name": "Test 1", "time": 5 }]"#)

        #expect(workout == Workout(name: "Workout", sport: "Workout", timers: [Interval(id: 0, name: "Test 1", time: 5)]))
    }

    @Test("fills missing fields with defaults")
    func missingFields() throws {
        #expect(try parse(#"{ "timers": [] }"#) == Workout.empty)
        #expect(try parse("{}") == Workout.empty)
    }

    @Test("keeps interval order")
    func order() throws {
        let workout = try parse(
            #"[{ "id": 1, "name": "B", "time": 2 }, { "id": 0, "name": "A", "time": 1 }]"#
        )

        #expect(workout.timers.map(\.name) == ["B", "A"])
        #expect(workout.totalTime == 3)
    }

    @Test("rejects invalid json and wrong shapes")
    func invalid() {
        #expect(throws: (any Error).self) { try parse("not json") }
        #expect(throws: (any Error).self) { try parse("null") }
        #expect(throws: (any Error).self) { try parse(#"[{ "name": "no time" }]"#) }
    }

    @Test("round-trips through JSONEncoder")
    func roundTrip() throws {
        let workout = Workout(name: "Yoga", sport: "Yoga", timers: [Interval(id: 0, name: "Cat-Cow", time: 90)])
        let data = try JSONEncoder().encode(workout)

        #expect(try WorkoutParser.parse(data) == workout)
    }
}

@Suite("formatTime")
struct FormatTimeTests {
    @Test(arguments: [
        (0, "00:00"), (5, "00:05"), (42, "00:42"), (60, "01:00"),
        (65, "01:05"), (126, "02:06"), (3600, "60:00"), (3723, "62:03"),
    ])
    func formats(seconds: Int, expected: String) {
        #expect(formatTime(seconds) == expected)
    }
}

private final class FixtureBundle {}

@Suite("yoga.json fixture")
struct FixtureTests {
    @Test("parses the real workout file")
    func realFile() throws {
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "yoga", withExtension: "json"))
        let workout = try WorkoutParser.parse(Data(contentsOf: url))

        #expect(workout.name == "Yoga")
        #expect(workout.sport == "Yoga")
        #expect(workout.timers.count == 16)
        #expect(workout.timers.last == Interval(id: 15, name: "Child’s Pose", time: 180))
    }
}
