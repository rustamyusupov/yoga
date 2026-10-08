import AuthenticationServices
import UIKit

/// Runs the Strava OAuth flow in `ASWebAuthenticationSession` and returns the `code`.
@MainActor
final class StravaAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let scheme = "yoga"
    /// Strava checks the host against the app's "Authorization Callback Domain".
    static let redirectURI = "\(scheme)://timer.rstm.me/strava"

    enum Failure: Error {
        case cancelled
        case noCode
    }

    private var session: ASWebAuthenticationSession?

    func authorize(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.scheme) { callback, error in
                if let error {
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    continuation.resume(throwing: cancelled ? Failure.cancelled : error)
                    return
                }

                let code = callback
                    .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                    .queryItems?
                    .first { $0.name == "code" }?
                    .value

                if let code {
                    continuation.resume(returning: code)
                } else {
                    continuation.resume(throwing: Failure.noCode)
                }
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
