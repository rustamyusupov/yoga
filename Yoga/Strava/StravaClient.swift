import Foundation
import Observation

/// Strava OAuth tokens and manual activity upload — `createStrava` from `strava.js`.
@MainActor
@Observable
final class StravaClient {
    enum Status: Equatable {
        case disconnected
        case connected
        case sending
        case failed
    }

    enum Failure: Error, Equatable {
        case notConnected
        case missingCredentials
        case http(Int)
    }

    typealias Request = @Sendable (URLRequest) async throws -> (Data, Int)

    private(set) var status: Status = .disconnected
    private(set) var pending: (Workout, WorkoutSummary)?

    @ObservationIgnored private(set) var config: StravaConfig {
        didSet { save() }
    }

    @ObservationIgnored private let store: SecretStore
    @ObservationIgnored private let request: Request
    @ObservationIgnored private let now: () -> Date

    static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    static let activitiesURL = URL(string: "https://www.strava.com/api/v3/activities")!
    private static let expiryMargin: TimeInterval = 60

    init(
        store: SecretStore = KeychainStore(),
        request: @escaping Request = StravaClient.send,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.request = request
        self.now = now
        config = store.read().flatMap { try? JSONDecoder().decode(StravaConfig.self, from: $0) } ?? StravaConfig()
        status = config.isConnected ? .connected : .disconnected

        // `-stravaClientId X -stravaClientSecret Y` launch arguments (simulator convenience)
        let arguments = UserDefaults.standard
        if !config.hasCredentials,
           let clientId = arguments.string(forKey: "stravaClientId"),
           let clientSecret = arguments.string(forKey: "stravaClientSecret") {
            setCredentials(clientId: clientId, clientSecret: clientSecret)
        }
    }

    var isConnected: Bool { config.isConnected }
    var hasCredentials: Bool { config.hasCredentials }

    // MARK: Credentials & OAuth

    func setCredentials(clientId: String, clientSecret: String) {
        config.clientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        config.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func authorizeURL(redirectURI: String) throws -> URL {
        guard let clientId = config.clientId, config.hasCredentials else {
            throw Failure.missingCredentials
        }

        var components = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: "activity:write"),
        ]

        return components.url!
    }

    /// Exchanges the OAuth `code` from the redirect for tokens.
    func exchange(code: String) async throws {
        _ = try await requestToken([("grant_type", "authorization_code"), ("code", code)])
        status = .connected
    }

    func disconnect() {
        config = StravaConfig(clientId: config.clientId, clientSecret: config.clientSecret)
        status = .disconnected
    }

    private func requestToken(_ body: [(String, String)]) async throws -> String {
        guard let clientId = config.clientId, let clientSecret = config.clientSecret, config.hasCredentials else {
            throw Failure.missingCredentials
        }

        var urlRequest = URLRequest(url: Self.tokenURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = ([("client_id", clientId), ("client_secret", clientSecret)] + body).formEncoded

        let (data, code) = try await request(urlRequest)

        guard (200 ..< 300).contains(code) else {
            throw Failure.http(code)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        config.accessToken = token.accessToken
        config.refreshToken = token.refreshToken
        config.expiresAt = token.expiresAt

        return token.accessToken
    }

    private func accessToken() async throws -> String {
        if let token = config.accessToken, let expiresAt = config.expiresAt,
           expiresAt - Self.expiryMargin > now().timeIntervalSince1970 {
            return token
        }

        guard let refreshToken = config.refreshToken, config.isConnected else {
            throw Failure.notConnected
        }

        return try await requestToken([("grant_type", "refresh_token"), ("refresh_token", refreshToken)])
    }

    // MARK: Upload

    func upload(workout: Workout, summary: WorkoutSummary) async throws {
        let token = try await accessToken()

        var urlRequest = URLRequest(url: Self.activitiesURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = StravaActivity.build(workout: workout, summary: summary).formEncoded

        let (_, code) = try await request(urlRequest)

        // 409: Strava already has this activity (e.g. a retry) — the upload succeeded
        guard (200 ..< 300).contains(code) || code == 409 else {
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
            print("strava upload:", error)
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
        if let data = try? JSONEncoder().encode(config) {
            store.write(data)
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
        }
    }

    private static let send: Request = { request in
        let (data, response) = try await URLSession.shared.data(for: request)

        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
