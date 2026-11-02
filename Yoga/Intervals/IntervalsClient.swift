import Foundation
import Observation

/// Intervals.icu API key and manual activity upload.
@MainActor
@Observable
final class IntervalsClient {
    enum Status: Equatable {
        case disconnected
        case connected
        case sending
        case failed
    }

    enum Failure: Error, Equatable {
        case notConnected
        case http(Int)
    }

    typealias Request = @Sendable (URLRequest) async throws -> (Data, Int)

    private(set) var status: Status = .disconnected
    private(set) var pending: (Workout, WorkoutSummary)?

    @ObservationIgnored private var apiKey: String? {
        didSet { save() }
    }

    @ObservationIgnored private let store: SecretStore
    @ObservationIgnored private let request: Request

    /// Athlete `0` is the owner of the API key; bulk upserts on `external_id`.
    static let activitiesURL = URL(string: "https://intervals.icu/api/v1/athlete/0/activities/manual/bulk")!

    init(
        store: SecretStore = KeychainStore(account: "intervals"),
        request: @escaping Request = IntervalsClient.send
    ) {
        self.store = store
        self.request = request
        apiKey = store.read().map { String(decoding: $0, as: UTF8.self) }
        status = isConnected ? .connected : .disconnected
    }

    var isConnected: Bool { !(apiKey ?? "").isEmpty }

    /// Key from intervals.icu/settings → Developer Settings.
    func setAPIKey(_ key: String) {
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        status = isConnected ? .connected : .disconnected
    }

    // MARK: Upload

    func upload(workout: Workout, summary: WorkoutSummary) async throws {
        guard let apiKey, isConnected else {
            throw Failure.notConnected
        }

        let credentials = Data("API_KEY:\(apiKey)".utf8).base64EncodedString()

        var urlRequest = URLRequest(url: Self.activitiesURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode([IntervalsActivity.build(workout: workout, summary: summary)])

        let (_, code) = try await request(urlRequest)

        guard (200 ..< 300).contains(code) else {
            throw Failure.http(code)
        }
    }

    /// Sends the finished workout; on failure keeps it for `retry()`.
    func send(workout: Workout, summary: WorkoutSummary) async {
        guard isConnected else { return }

        pending = nil
        status = .sending

        do {
            try await upload(workout: workout, summary: summary)
            status = .connected
        } catch {
            print("intervals upload:", error)
            pending = (workout, summary)
            status = .failed
        }
    }

    func retry() async {
        guard let (workout, summary) = pending else { return }

        await send(workout: workout, summary: summary)
    }

    // MARK: Persistence & transport

    private func save() {
        if let apiKey, !apiKey.isEmpty {
            store.write(Data(apiKey.utf8))
        } else {
            store.delete()
        }
    }

    private static let send: Request = { request in
        let (data, response) = try await URLSession.shared.data(for: request)

        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
