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

@Suite("IntervalsActivity")
struct IntervalsActivityTests {
    @Test("builds the manual activity with a stable external id")
    func build() throws {
        let activity = IntervalsActivity.build(workout: workout, summary: summary, timeZone: TimeZone(identifier: "Europe/Moscow")!)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(activity)) as! [String: Any]

        #expect(json["external_id"] as? String == "yoga-1783504800")
        #expect(json["type"] as? String == "Yoga")
        #expect(json["name"] as? String == "Yoga")
        #expect(json["start_date_local"] as? String == "2026-07-08T13:00:00")
        #expect(json["elapsed_time"] as? Int == 272)
        #expect(json["moving_time"] as? Int == 272)
        #expect(json["description"] as? String == "Cat-Cow — 01:30\nChild’s Pose — 03:00")
    }
}

@MainActor
@Suite("IntervalsClient")
struct IntervalsClientTests {
    private let store = MemoryStore()
    private let requests = Requests()

    private func client(apiKey: String? = "key", responses: [(Data, Int)]) -> IntervalsClient {
        if let apiKey {
            store.write(Data(apiKey.utf8))
        }
        requests.set(responses)

        return IntervalsClient(store: store, request: { [requests] in requests.handle($0) })
    }

    @Test("starts disconnected without an API key")
    func disconnected() async {
        let client = client(apiKey: nil, responses: [])

        #expect(client.status == .disconnected)

        await client.send(workout: workout, summary: summary)
        #expect(requests.sent.isEmpty)
    }

    @Test("uploads one activity with basic auth")
    func upload() async throws {
        let client = client(responses: [(Data("[]".utf8), 200)])

        await client.send(workout: workout, summary: summary)

        let sent = requests.sent
        let body = try JSONSerialization.jsonObject(with: sent[0].httpBody!) as! [[String: Any]]
        #expect(client.status == .connected)
        #expect(sent.count == 1)
        #expect(sent[0].url == IntervalsClient.activitiesURL)
        #expect(sent[0].value(forHTTPHeaderField: "Authorization") == "Basic QVBJX0tFWTprZXk=") // API_KEY:key
        #expect(body.count == 1)
        #expect(body[0]["external_id"] as? String == "yoga-1783504800")
    }

    @Test("failure keeps the summary for retry")
    func retry() async {
        let client = client(responses: [(Data(), 500), (Data("[]".utf8), 200)])

        await client.send(workout: workout, summary: summary)
        #expect(client.status == .failed)
        #expect(client.pending?.1 == summary)

        await client.retry()
        #expect(client.status == .connected)
        #expect(client.pending == nil)
        #expect(requests.sent.count == 2)
    }

    @Test("stores a trimmed key and clears an empty one")
    func setAPIKey() {
        let client = client(apiKey: nil, responses: [])

        client.setAPIKey("  abc \n")
        #expect(client.status == .connected)
        #expect(store.read() == Data("abc".utf8))

        client.setAPIKey("")
        #expect(client.status == .disconnected)
        #expect(store.read() == nil)
    }
}
