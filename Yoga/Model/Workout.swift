import Foundation

/// Same format as the web app: `{ "name", "sport", "timers": [...] }`
/// or a bare `timers` array. Missing `name`/`sport` default to `Workout`.
struct Workout: Codable, Equatable, Sendable {
    static let defaultName = "Workout"
    static let empty = Workout(name: defaultName, sport: defaultName, timers: [])

    var name: String
    var sport: String
    var timers: [Interval]

    init(name: String = defaultName, sport: String = defaultName, timers: [Interval]) {
        self.name = name
        self.sport = sport
        self.timers = timers
    }

    var totalTime: Int {
        timers.reduce(0) { $0 + $1.time }
    }

    private enum CodingKeys: String, CodingKey {
        case name, sport, timers
    }

    init(from decoder: Decoder) throws {
        if let timers = try? decoder.singleValueContainer().decode([Interval].self) {
            self.init(timers: timers)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let sport = try container.decodeIfPresent(String.self, forKey: .sport)
        let timers = try container.decodeIfPresent([Interval].self, forKey: .timers)

        self.init(
            name: name ?? Self.defaultName,
            sport: sport ?? Self.defaultName,
            timers: timers ?? []
        )
    }
}

enum WorkoutParser {
    static func parse(_ data: Data) throws -> Workout {
        try JSONDecoder().decode(Workout.self, from: data)
    }
}
