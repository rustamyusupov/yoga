import Foundation
import Testing
@testable import Yoga

private let workout = Workout(
    name: "Yoga",
    sport: "Yoga",
    timers: [Interval(id: 0, name: "Cat-Cow", time: 90), Interval(id: 1, name: "Child’s Pose", time: 180)]
)
private let startedAt = Date(timeIntervalSince1970: 1_783_504_800) // 2026-07-08T10:00:00Z
private let summary = WorkoutSummary(startedAt: startedAt, elapsed: 272, timers: workout.timers)

@Suite("StravaActivity")
struct StravaActivityTests {
    @Test("builds the manual activity like the web app")
    func build() {
        let fields = StravaActivity.build(workout: workout, summary: summary, timeZone: TimeZone(identifier: "Europe/Moscow")!)

        #expect(fields.map(\.0) == ["name", "sport_type", "start_date_local", "elapsed_time", "description"])
        #expect(fields.map(\.1) == ["Yoga", "Yoga", "2026-07-08T13:00:00", "272", "Cat-Cow — 01:30\nChild’s Pose — 03:00"])
    }

    @Test("local ISO has no offset and follows the time zone")
    func localISO() {
        #expect(StravaActivity.localISO(startedAt, timeZone: TimeZone(identifier: "UTC")!) == "2026-07-08T10:00:00")
        #expect(StravaActivity.localISO(startedAt, timeZone: TimeZone(identifier: "America/New_York")!) == "2026-07-08T06:00:00")
    }

    @Test("form encodes reserved characters")
    func formEncoded() {
        let body = String(decoding: [("a", "x y&z=1+2"), ("b", "ok")].formEncoded, as: UTF8.self)

        #expect(body == "a=x%20y%26z%3D1%2B2&b=ok")
    }
}

@MainActor
@Suite("StravaClient")
struct StravaClientTests {
    private let store = MemoryStore()
    private let requests = Requests()

    private func client(
        _ config: StravaConfig = StravaConfig(clientId: "1", clientSecret: "s", accessToken: "old", refreshToken: "r", expiresAt: 2_000_000_000),
        now: Date = Date(timeIntervalSince1970: 1_900_000_000),
        responses: [(Data, Int)]
    ) -> StravaClient {
        store.write(try! JSONEncoder().encode(config))
        requests.set(responses)

        return StravaClient(store: store, request: { [requests] in requests.handle($0) }, now: { now })
    }

    private func stored() -> StravaConfig {
        try! JSONDecoder().decode(StravaConfig.self, from: store.read()!)
    }

    @Test("starts disconnected without a refresh token")
    func disconnected() async {
        let client = client(StravaConfig(), responses: [])

        #expect(client.status == .disconnected)
        #expect(!client.hasCredentials)

        await client.send(workout: workout, summary: summary)
        #expect(requests.sent.isEmpty)
    }

    @Test("uploads with a valid access token")
    func upload() async {
        let client = client(responses: [(Data("{}".utf8), 201)])

        await client.send(workout: workout, summary: summary)

        let sent = requests.sent
        #expect(client.status == .connected)
        #expect(sent.count == 1)
        #expect(sent[0].url == StravaClient.activitiesURL)
        #expect(sent[0].value(forHTTPHeaderField: "Authorization") == "Bearer old")
        #expect(String(decoding: sent[0].httpBody!, as: UTF8.self).hasPrefix("name=Yoga&sport_type=Yoga&start_date_local="))
    }

    @Test("refreshes an expired token first and stores the new one")
    func refresh() async {
        let token = #"{ "access_token": "new", "refresh_token": "r2", "expires_at": 1900021600 }"#
        let client = client(
            StravaConfig(clientId: "1", clientSecret: "s", accessToken: "old", refreshToken: "r", expiresAt: 1_900_000_030),
            responses: [(Data(token.utf8), 200), (Data("{}".utf8), 201)]
        )

        await client.send(workout: workout, summary: summary)

        let sent = requests.sent
        #expect(sent.count == 2)
        #expect(sent[0].url == StravaClient.tokenURL)
        #expect(String(decoding: sent[0].httpBody!, as: UTF8.self) == "client_id=1&client_secret=s&grant_type=refresh_token&refresh_token=r")
        #expect(sent[1].value(forHTTPHeaderField: "Authorization") == "Bearer new")
        #expect(stored().accessToken == "new")
        #expect(stored().refreshToken == "r2")
        #expect(client.status == .connected)
    }

    @Test("409 counts as success")
    func conflict() async {
        let client = client(responses: [(Data(), 409)])

        await client.send(workout: workout, summary: summary)

        #expect(client.status == .connected)
        #expect(client.pending == nil)
    }

    @Test("failure keeps the summary for retry")
    func retry() async {
        let client = client(responses: [(Data(), 500), (Data("{}".utf8), 201)])

        await client.send(workout: workout, summary: summary)
        #expect(client.status == .failed)
        #expect(client.pending?.1 == summary)

        await client.retry()
        #expect(client.status == .connected)
        #expect(client.pending == nil)
        #expect(requests.sent.count == 2)
    }

    @Test("exchange stores tokens and connects")
    func exchange() async throws {
        let token = #"{ "access_token": "a", "refresh_token": "r", "expires_at": 1900021600 }"#
        let client = client(StravaConfig(clientId: "1", clientSecret: "s"), responses: [(Data(token.utf8), 200)])

        try await client.exchange(code: "abc")

        #expect(client.status == .connected)
        #expect(stored() == StravaConfig(clientId: "1", clientSecret: "s", accessToken: "a", refreshToken: "r", expiresAt: 1_900_021_600))
        #expect(String(decoding: requests.sent[0].httpBody!, as: UTF8.self) == "client_id=1&client_secret=s&grant_type=authorization_code&code=abc")
    }

    @Test("authorize url carries the scope and redirect")
    func authorizeURL() throws {
        let client = client(StravaConfig(clientId: "42", clientSecret: "s"), responses: [])
        let url = try client.authorizeURL(redirectURI: "yoga://timer.rstm.me/strava")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!

        #expect(url.host == "www.strava.com")
        #expect(items.first { $0.name == "client_id" }?.value == "42")
        #expect(items.first { $0.name == "scope" }?.value == "activity:write")
        #expect(items.first { $0.name == "redirect_uri" }?.value == "yoga://timer.rstm.me/strava")
        #expect(throws: StravaClient.Failure.missingCredentials) {
            try self.client(StravaConfig(), responses: []).authorizeURL(redirectURI: "x")
        }
    }
}

/// Canned responses; the lock keeps it `Sendable` for the client's request closure.
private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [(Data, Int)] = []
    private var _sent: [URLRequest] = []

    var sent: [URLRequest] {
        lock.withLock { _sent }
    }

    func set(_ responses: [(Data, Int)]) {
        lock.withLock { self.responses = responses }
    }

    func handle(_ request: URLRequest) -> (Data, Int) {
        lock.withLock {
            _sent.append(request)

            return responses.isEmpty ? (Data(), 500) : responses.removeFirst()
        }
    }
}
