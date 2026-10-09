import SwiftUI

struct WorkoutView: View {
    let workout: Workout
    let timer: WorkoutTimer
    let strava: StravaClient

    var body: some View {
        VStack(spacing: 24) {
            TimerDisplay(seconds: timer.seconds)
                // the rounded font carries a lot of internal leading
                .padding(.top, -4)
                .padding(.bottom, -14)

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

            ScrollViewReader { proxy in
                List {
                    ForEach(Array(workout.timers.enumerated()), id: \.element.id) { index, interval in
                        IntervalRow(interval: interval, isActive: index == timer.activeIndex)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .id(interval.id)
                    }

                    FooterView(strava: strava)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
                .padding(.top, 8)
                .environment(\.defaultMinListRowHeight, 40)
                .onChange(of: timer.activeIndex) { _, index in
                    guard let index, workout.timers.indices.contains(index) else { return }

                    withAnimation {
                        proxy.scrollTo(workout.timers[index].id, anchor: .center)
                    }
                }
            }
        }
        .padding(.top, 16)
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
    let strava: StravaClient

    var body: some View {
        HStack {
            StravaButton(strava: strava)
            Spacer()
            Text(AppInfo.version)
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
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
        WorkoutView(
            workout: workout,
            timer: WorkoutTimer(timers: workout.timers),
            strava: StravaClient(store: MemoryStore())
        )
        .navigationTitle("Yoga")
    }
}
