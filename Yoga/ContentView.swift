import SwiftUI

struct ContentView: View {
    @State private var store = WorkoutStore()
    @State private var timer = WorkoutTimer(timers: [])
    @State private var sounds = WorkoutSounds(player: SoundPlayer())

    var body: some View {
        NavigationStack {
            Group {
                if let workout = store.workout, !workout.timers.isEmpty {
                    WorkoutView(workout: workout, timer: timer)
                } else {
                    EmptyWorkoutView(action: importFromPasteboard)
                }
            }
            .navigationTitle(store.workout?.name ?? "Yoga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Paste URL", systemImage: "doc.on.clipboard", action: importFromPasteboard)
                        Button("Reload", systemImage: "arrow.clockwise") {
                            Task { await store.reload() }
                        }
                        .disabled(store.url == nil)
                    } label: {
                        if store.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis")
                        }
                    }
                    .disabled(store.isLoading)
                }
            }
            .alert("Import failed", isPresented: hasError) {
                Button("OK") { store.error = nil }
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            if store.workout == nil, store.url != nil {
                await store.reload()
            }
        }
        .onChange(of: store.workout, initial: true) { _, workout in
            timer.reset()
            timer = WorkoutTimer(timers: workout?.timers ?? [], onEvent: sounds.handle)
        }
        .onChange(of: timer.isRunning) { _, isRunning in
            // keep the screen on while the workout runs in the foreground
            UIApplication.shared.isIdleTimerDisabled = isRunning

            if isRunning {
                sounds.player.startWorkout()
            } else {
                sounds.player.endWorkout()
            }
        }
    }

    private var hasError: Binding<Bool> {
        Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
    }

    private var errorMessage: String {
        switch store.error {
        case .noURL: "Copy a workout JSON link first."
        case .badResponse(let status): "Could not download the workout (\(status))."
        case .invalidWorkout: "The link does not point to a valid workout."
        case nil: ""
        }
    }

    private func importFromPasteboard() {
        let url = Pasteboard.url()
        Task { await store.load(from: url) }
    }
}

#Preview {
    ContentView()
}
