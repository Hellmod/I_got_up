import SwiftUI

// MARK: - WakeUpCheckView
//
// The in-app wake-up verification screen with two countdown phases:
//   Phase 1 (delay):   a timer counts down the configured delay — the confirm
//                      button is locked so you can't dismiss the check in
//                      half-sleep right after stopping the alarm.
//   Phase 2 (response): a second timer shows how long until the alarm rings
//                      again — now "Yes, I'm up" (and "Not yet") are active.

struct WakeUpCheckView: View {
    let alarm: Alarm

    @EnvironmentObject private var alarmKit: AlarmKitManager
    @EnvironmentObject private var historyStore: AlarmHistoryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                content(now: timeline.date)
            }
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private func content(now: Date) -> some View {
        let state = alarmKit.wakeCheckState(for: alarm.id)
        // Without stored state (stale entry) fall back to an unlocked confirm.
        let delayEnd = state?.delayEnd ?? now
        let ringDate = state?.ringDate ?? now
        let inDelayPhase = now < delayEnd

        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Image(systemName: inDelayPhase ? "hourglass" : "sun.max.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(inDelayPhase ? .orange : .yellow)

                Text("Are you up yet?")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                VStack(spacing: 4) {
                    Text("Alarm \(alarm.timeString)")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                    if !alarm.label.isEmpty {
                        Text(alarm.label)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                VStack(spacing: 6) {
                    Text(inDelayPhase ? "You can confirm in:" : "Alarm will ring again in:")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))

                    Text(timerInterval: now...max(inDelayPhase ? delayEnd : ringDate, now),
                         countsDown: true)
                        .font(.system(size: 56, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .foregroundStyle(inDelayPhase ? .orange : .white)

                    if inDelayPhase {
                        Text("The confirm button unlocks when the countdown ends.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .padding(.top, 8)
            }

            Spacer()

            VStack(spacing: 14) {
                Button(action: confirm) {
                    Label("Yes, I'm up", systemImage: inDelayPhase ? "lock.fill" : "checkmark.circle.fill")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(inDelayPhase ? Color.gray.opacity(0.35) : Color.green)
                        .foregroundStyle(inDelayPhase ? .white.opacity(0.5) : .white)
                        .cornerRadius(18)
                }
                .disabled(inDelayPhase)

                if !inDelayPhase {
                    Button(action: postpone) {
                        Label("Not yet — alarm in 5 min", systemImage: "moon.zzz.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .cornerRadius(18)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 56)
        }
    }

    // MARK: - Actions

    private func confirm() {
        historyStore.record(alarm: alarm, action: .wakeConfirmed)
        alarmKit.cancelWakeUpCheck(for: alarm.id)
        alarmKit.pendingWakeUpAlarm = nil
    }

    private func postpone() {
        historyStore.record(alarm: alarm, action: .wakePostponed)
        Task { await alarmKit.postponeWakeUpCheck(for: alarm) }
        alarmKit.pendingWakeUpAlarm = nil
    }
}

#Preview {
    WakeUpCheckView(
        alarm: Alarm(id: UUID(), hour: 7, minute: 30, label: "Praca")
    )
    .environmentObject(AlarmKitManager.shared)
    .environmentObject(AlarmHistoryStore())
}
