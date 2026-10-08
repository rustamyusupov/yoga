import SwiftUI

struct WorkoutView: View {
    let workout: Workout

    // Timer state comes in step 3; for now the display shows the first interval.
    private var seconds: Int { workout.timers.first?.time ?? 0 }
    private var activeIndex: Int? { nil }
    private var isRunning: Bool { false }

    var body: some View {
        VStack(spacing: 16) {
            TimerDisplay(seconds: seconds)
                // the rounded font carries a lot of internal leading
                .padding(.top, -8)
                .padding(.bottom, -18)

            HStack(spacing: 16) {
                Button {} label: {
                    Text("Reset").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {} label: {
                    Text(isRunning ? "Stop" : "Start").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .red : .green)
            }
            .controlSize(.large)
            .fontWeight(.semibold)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 16)

            List {
                ForEach(Array(workout.timers.enumerated()), id: \.element.id) { index, interval in
                    IntervalRow(interval: interval, isActive: index == activeIndex)
                        .listRowSeparator(index == workout.timers.count - 1 ? .hidden : .visible, edges: .bottom)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 40)

            FooterView()
                .padding(.top, -16)
        }
    }
}

struct TimerDisplay: View {
    let seconds: Int

    var body: some View {
        Text(formatTime(seconds))
            .font(.system(size: 96, weight: .light, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityLabel("Remaining time")
    }
}

struct IntervalRow: View {
    let interval: Interval
    let isActive: Bool

    var body: some View {
        HStack {
            Text(interval.name)
            Spacer()
            Text(formatTime(interval.time))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .fontWeight(isActive ? .bold : .regular)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.2) : nil)
    }
}

struct FooterView: View {
    var body: some View {
        HStack {
            Text(AppInfo.version)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Connect Strava") {}
                .font(.footnote)
                .disabled(true)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    NavigationStack {
        WorkoutView(workout: Workout(
            name: "Yoga",
            sport: "Yoga",
            timers: [
                Interval(id: 0, name: "Cat-Cow", time: 90),
                Interval(id: 1, name: "Child’s Pose", time: 180),
            ]
        ))
        .navigationTitle("Yoga")
    }
}
