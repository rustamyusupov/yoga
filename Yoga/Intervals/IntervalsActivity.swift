import Foundation

/// Manual activity for `POST /athlete/{id}/activities/manual/bulk`.
struct IntervalsActivity: Encodable, Equatable {
    let externalId: String
    let type: String
    let name: String
    let startDateLocal: String
    let elapsedTime: Int
    let movingTime: Int
    let description: String

    enum CodingKeys: String, CodingKey {
        case externalId = "external_id"
        case type, name
        case startDateLocal = "start_date_local"
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case description
    }

    static func build(
        workout: Workout,
        summary: WorkoutSummary,
        timeZone: TimeZone = .current
    ) -> IntervalsActivity {
        IntervalsActivity(
            // stable per workout, so a retry updates instead of duplicating
            externalId: "yoga-\(Int(summary.startedAt.timeIntervalSince1970))",
            type: workout.sport,
            name: workout.name,
            startDateLocal: StravaActivity.localISO(summary.startedAt, timeZone: timeZone),
            elapsedTime: summary.elapsed,
            movingTime: summary.elapsed,
            description: StravaActivity.description(summary)
        )
    }
}
