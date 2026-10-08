import SwiftUI

struct WorkoutView: View {
    let workout: Workout
    let timer: WorkoutTimer

    var body: some View {
        VStack(spacing: 16) {
            TimerDisplay(seconds: timer.seconds)
                // the rounded font carries a lot of internal leading
                .padding(.top, -8)
                .padding(.bottom, -18)

            HStack(spacing: 16) {
                Button(action: timer.reset) {
                    Text("Reset").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: timer.toggle) {
                    Text(timer.isRunning ? "Stop" : "Start").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(timer.isRunning ? .red : .green)
            }
            .controlSize(.large)
            .fontWeight(.semibold)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 16)

            List {
                ForEach(Array(workout.timers.enumerated()), id: \.element.id) { index, interval in
                    IntervalRow(interval: interval, isActive: index == timer.activeIndex)
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
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
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
    let workout = Workout(
        name: "Yoga",
        sport: "Yoga",
        timers: [
            Interval(id: 0, name: "Cat-Cow", time: 90),
            Interval(id: 1, name: "Child’s Pose", time: 180),
        ]
    )

    NavigationStack {
        WorkoutView(workout: workout, timer: WorkoutTimer(timers: workout.timers))
            .navigationTitle("Yoga")
    }
}
