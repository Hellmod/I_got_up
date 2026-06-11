import SwiftUI

// MARK: - WakeUpCheckView
//
// Shown full-screen when the user taps the body of a Wake-Up Check notification.
// The same actions are available by long-pressing the notification, but this
// screen makes them obvious for users who don't know about long-press.

struct WakeUpCheckView: View {
    let alarm: Alarm

    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var historyStore: AlarmHistoryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.yellow)

                    Text("Czy już wstałeś?")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    VStack(spacing: 4) {
                        Text("Budzik \(alarm.timeString)")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.6))
                        if !alarm.label.isEmpty {
                            Text(alarm.label)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Text("Potwierdź, że nie śpisz — inaczej alarm zadzwoni ponownie.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 14) {
                    Button(action: confirm) {
                        Label("Tak, wstałem", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .cornerRadius(18)
                    }

                    Button(action: postpone) {
                        Label("Jeszcze nie — alarm za 5 min", systemImage: "moon.zzz.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(.white)
                            .cornerRadius(18)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 56)
            }
        }
    }

    // MARK: - Actions

    private func confirm() {
        historyStore.record(alarm: alarm, action: .wakeConfirmed)
        notificationManager.cancelWakeUpCheck(for: alarm.id)
        notificationManager.pendingWakeUpAlarm = nil
    }

    private func postpone() {
        historyStore.record(alarm: alarm, action: .wakePostponed)
        notificationManager.cancelWakeUpCheck(for: alarm.id)
        Task { await AlarmKitManager.shared.scheduleReRing(for: alarm, after: 5 * 60) }
        notificationManager.pendingWakeUpAlarm = nil
    }
}

#Preview {
    WakeUpCheckView(
        alarm: Alarm(id: UUID(), hour: 7, minute: 30, label: "Praca")
    )
    .environmentObject(NotificationManager.shared)
    .environmentObject(AlarmHistoryStore())
}
