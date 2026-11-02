import SwiftUI

/// Footer button: Connect Intervals / Intervals ✓ / Sending… / failed — retry.
struct IntervalsButton: View {
    let intervals: IntervalsClient
    @State private var askKey = false
    @State private var apiKey = ""

    var body: some View {
        Button(label, action: tap)
            .font(.footnote)
            .disabled(intervals.status == .sending)
            .alert("Intervals.icu API", isPresented: $askKey) {
                SecureField("API key", text: $apiKey)
                Button("Save") {
                    intervals.setAPIKey(apiKey)
                    apiKey = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("From intervals.icu/settings, Developer Settings. Stored in the Keychain.")
            }
    }

    private var label: String {
        switch intervals.status {
        case .disconnected: "Connect Intervals"
        case .connected: "Intervals ✓"
        case .sending: "Sending to Intervals…"
        case .failed: "Intervals failed — retry"
        }
    }

    private func tap() {
        if intervals.status == .failed {
            Task { await intervals.retry() }
        } else {
            askKey = true
        }
    }
}
