import SwiftUI
import AudioToolbox
import AVFoundation

// MARK: - AlarmSoundPlayer

/// Loops an alert sound using AudioServices until stopped.
/// Configures AVAudioSession for playback so audio continues when the screen locks.
final class AlarmSoundPlayer: ObservableObject {
    private var active = false

    func start() {
        active = true
        configureSession()
        loop()
    }

    func stop() {
        active = false
        try? AVAudioSession.sharedInstance().setActive(false,
              options: .notifyOthersOnDeactivation)
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func loop() {
        guard active else { return }
        AudioServicesPlayAlertSoundWithCompletion(SystemSoundID(1005)) { [weak self] in
            guard self?.active == true else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.loop()
            }
        }
    }
}

// MARK: - AlarmActiveView

struct AlarmActiveView: View {
    let alarm: Alarm

    @EnvironmentObject private var notificationManager: NotificationManager
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var historyStore: AlarmHistoryStore
    @StateObject private var soundPlayer = AlarmSoundPlayer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Clock face
                VStack(spacing: 16) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)

                    Text(alarm.timeString)
                        .font(.system(size: 96, weight: .thin, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()

                    if !alarm.label.isEmpty {
                        Text(alarm.label)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: 14) {
                    Button(action: dismissAlarm) {
                        Label("Wyłącz alarm", systemImage: "xmark.circle.fill")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .cornerRadius(18)
                    }

                    HStack(spacing: 14) {
                        snoozeButton(minutes: alarm.snoozeDuration)
                        snoozeButton(minutes: alarm.snoozeDuration + 5)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 56)
            }
        }
        .onAppear { soundPlayer.start() }
        .onDisappear { soundPlayer.stop() }
    }

    // MARK: - Subviews

    private func snoozeButton(minutes: Int) -> some View {
        Button(action: { snooze(minutes: minutes) }) {
            VStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                Text("Drzemka \(minutes) min")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.white.opacity(0.12))
            .foregroundStyle(.white)
            .cornerRadius(18)
        }
    }

    // MARK: - Actions

    private func dismissAlarm() {
        soundPlayer.stop()
        historyStore.record(alarm: alarm, action: .dismissed)
        notificationManager.cancelAlarmBackups(for: alarm.id)
        notificationManager.cancelWakeUpCheck(for: alarm.id)
        notificationManager.firingAlarm = nil
        notificationManager.scheduleWakeUpCheck(for: alarm)
    }

    private func snooze(minutes: Int) {
        soundPlayer.stop()
        historyStore.record(alarm: alarm, action: .snoozed, detail: "\(minutes) min")
        notificationManager.cancelAlarmBackups(for: alarm.id)
        notificationManager.cancelWakeUpCheck(for: alarm.id)
        notificationManager.firingAlarm = nil
        notificationManager.scheduleSnooze(for: alarm, minutes: minutes)
    }
}

#Preview {
    AlarmActiveView(
        alarm: Alarm(id: UUID(), hour: 7, minute: 30, label: "Praca")
    )
    .environmentObject(NotificationManager.shared)
    .environmentObject(AlarmStore())
}
