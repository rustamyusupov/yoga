import SwiftUI

/// Footer button: Connect Strava / Strava ✓ / Sending… / failed — retry.
struct StravaButton: View {
    let strava: StravaClient
    @State private var auth = StravaAuth()
    @State private var askCredentials = false
    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var error: String?

    var body: some View {
        Button(label, action: tap)
            .font(.footnote)
            .disabled(strava.status == .sending)
            .alert("Strava API", isPresented: $askCredentials) {
                TextField("Client ID", text: $clientId)
                    .keyboardType(.numberPad)
                TextField("Client Secret", text: $clientSecret)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Connect") {
                    strava.setCredentials(clientId: clientId, clientSecret: clientSecret)
                    connect()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("From strava.com/settings/api. Stored in the Keychain.")
            }
            .alert("Strava", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
    }

    private var label: String {
        switch strava.status {
        case .disconnected: "Connect Strava"
        case .connected: "Strava ✓"
        case .sending: "Sending to Strava…"
        case .failed: "Strava failed — retry"
        }
    }

    private func tap() {
        if strava.status == .failed {
            Task { await strava.retry() }
        } else if strava.hasCredentials {
            connect()
        } else {
            askCredentials = true
        }
    }

    private func connect() {
        Task {
            do {
                let url = try strava.authorizeURL(redirectURI: StravaAuth.redirectURI)
                let code = try await auth.authorize(url: url)
                try await strava.exchange(code: code)
            } catch StravaAuth.Failure.cancelled {
                // user closed the browser
            } catch {
                self.error = "Authorization failed: \(error)"
            }
        }
    }
}
