import Foundation

/// Form fields of a Strava manual activity — `buildActivity` from `strava.js`.
enum StravaActivity {
    static func build(
        workout: Workout,
        summary: WorkoutSummary,
        timeZone: TimeZone = .current
    ) -> [(String, String)] {
        [
            ("name", workout.name),
            ("sport_type", workout.sport),
            ("start_date_local", localISO(summary.startedAt, timeZone: timeZone)),
            ("elapsed_time", String(summary.elapsed)),
            ("description", summary.timers.map { "\($0.name) — \(formatTime($0.time))" }.joined(separator: "\n")),
        ]
    }

    /// `yyyy-MM-ddTHH:mm:ss` in the given time zone, no offset — what Strava expects.
    static func localISO(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        return formatter.string(from: date)
    }
}

extension Array where Element == (String, String) {
    /// `application/x-www-form-urlencoded` body.
    var formEncoded: Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")

        return Data(
            map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
            .utf8
        )
    }
}
