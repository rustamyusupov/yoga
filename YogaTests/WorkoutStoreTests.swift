import Foundation
import Testing
@testable import Yoga

@MainActor
@Suite("WorkoutStore")
struct WorkoutStoreTests {
    private let defaults: UserDefaults
    private let url = URL(string: "https://example.com/yoga.json")!
    private let json = Data(#"{ "name": "Yoga", "sport": "Yoga", "timers": [{ "id": 0, "name": "Cat-Cow", "time": 90 }] }"#.utf8)
    private let workout = Workout(name: "Yoga", sport: "Yoga", timers: [Interval(id: 0, name: "Cat-Cow", time: 90)])

    init() {
        let suite = "WorkoutStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func store(_ fetch: @escaping WorkoutStore.Fetch) -> WorkoutStore {
        WorkoutStore(defaults: defaults, fetch: fetch)
    }

    @Test("starts empty")
    func empty() {
        let store = store { _ in Data() }

        #expect(store.workout == nil)
        #expect(store.url == nil)
        #expect(!store.hasWorkout)
    }

    @Test("import fetches the workout and remembers the url")
    func importSaves() async {
        let store = store { [json] _ in json }

        await store.load(from: url)

        #expect(store.workout == workout)
        #expect(store.url == url)
        #expect(store.error == nil)
        #expect(defaults.string(forKey: "workoutUrl") == url.absoluteString)
        #expect(defaults.data(forKey: "workout") == json)
    }

    @Test("opens the stored workout without touching the network")
    func restoresFromDefaults() async {
        await store { [json] _ in json }.load(from: url)

        let restored = store { _ in Issue.record("network must not be used"); return Data() }

        #expect(restored.workout == workout)
        #expect(restored.url == url)
        #expect(restored.hasWorkout)
    }

    @Test("reload uses the stored url")
    func reload() async {
        await store { [json] _ in json }.load(from: url)

        let requested = Requested()
        let updated = Data(#"[{ "id": 0, "name": "Bridge", "time": 60 }]"#.utf8)
        let store = store { url in await requested.add(url); return updated }

        await store.reload()

        #expect(await requested.urls == [url])
        #expect(store.workout?.timers.map(\.name) == ["Bridge"])
    }

    @Test("missing url is reported")
    func noURL() async {
        let store = store { _ in Data() }

        await store.load(from: nil)

        #expect(store.error == .noURL)
        await store.reload()
        #expect(store.error == .noURL)
    }

    @Test("failed download keeps the stored workout")
    func failedDownload() async {
        await store { [json] _ in json }.load(from: url)

        let store = store { _ in throw WorkoutStore.Failure.badResponse(404) }
        await store.reload()

        #expect(store.error == .badResponse(404))
        #expect(store.workout == workout)
    }

    @Test("invalid or empty json keeps the stored workout")
    func invalidJSON() async {
        await store { [json] _ in json }.load(from: url)

        let broken = store { _ in Data("oops".utf8) }
        await broken.reload()
        #expect(broken.error == .invalidWorkout)
        #expect(broken.workout == workout)

        let empty = store { _ in Data(#"{ "timers": [] }"#.utf8) }
        await empty.reload()
        #expect(empty.error == .invalidWorkout)
        #expect(empty.workout == workout)
    }
}

private actor Requested {
    var urls: [URL] = []

    func add(_ url: URL) {
        urls.append(url)
    }
}
