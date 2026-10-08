import SwiftUI

struct EmptyWorkoutView: View {
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No workout", systemImage: "figure.yoga")
        } description: {
            Text("Copy a link to a workout JSON and paste it here.")
        } actions: {
            Button("Paste URL", systemImage: "doc.on.clipboard", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}
