import Foundation

/// Everything Strava-related that is persisted (in the Keychain).
struct StravaConfig: Codable, Equatable, Sendable {
    var clientId: String?
    var clientSecret: String?
    var accessToken: String?
    var refreshToken: String?
    /// Unix timestamp, as returned by Strava.
    var expiresAt: TimeInterval?

    var hasCredentials: Bool {
        !(clientId ?? "").isEmpty && !(clientSecret ?? "").isEmpty
    }

    var isConnected: Bool {
        !(refreshToken ?? "").isEmpty
    }
}
