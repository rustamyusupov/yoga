import Foundation

/// Canned responses; the lock keeps it `Sendable` for the client's request closure.
final class Requests: @unchecked Sendable {
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
