import Foundation
import Observation

/// Keeps the imported workout and its source url in `UserDefaults`.
/// The workout is always opened from storage; the network is used only
/// on explicit import / reload — same as the web app.
@MainActor
@Observable
final class WorkoutStore {
    enum Failure: Error, Equatable {
        case noURL
        case badResponse(Int)
        case invalidWorkout
    }

    typealias Fetch = @Sendable (URL) async throws -> Data

    private(set) var workout: Workout?
    private(set) var url: URL?
    private(set) var isLoading = false
    var error: Failure?

    private let defaults: UserDefaults
    private let fetch: Fetch

    init(defaults: UserDefaults = .standard, fetch: @escaping Fetch = WorkoutStore.download) {
        self.defaults = defaults
        self.fetch = fetch

        url = defaults.string(forKey: Keys.url).flatMap(URL.init)
        workout = defaults.data(forKey: Keys.workout).flatMap { try? WorkoutParser.parse($0) }
    }

    var hasWorkout: Bool {
        !(workout?.timers.isEmpty ?? true)
    }

    /// Imports the workout from `url` (taken from the pasteboard by the caller).
    func load(from url: URL?) async {
        guard let url else {
            error = .noURL
            return
        }

        error = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await fetch(url)
            let parsed = try WorkoutParser.parse(data)

            guard !parsed.timers.isEmpty else {
                throw Failure.invalidWorkout
            }

            workout = parsed
            self.url = url
            defaults.set(url.absoluteString, forKey: Keys.url)
            defaults.set(data, forKey: Keys.workout)
        } catch let failure as Failure {
            error = failure
        } catch is DecodingError {
            error = .invalidWorkout
        } catch {
            self.error = .badResponse(0)
        }
    }

    /// Reloads the workout from the stored url.
    func reload() async {
        await load(from: url)
    }

    private enum Keys {
        static let url = "workoutUrl"
        static let workout = "workout"
    }

    private static let download: Fetch = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200 ..< 300).contains(status) else {
            throw Failure.badResponse(status)
        }

        return data
    }
}
