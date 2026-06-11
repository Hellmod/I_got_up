import AlarmKit
import AppIntents
import SwiftUI

// MARK: - AlarmKitManager
// (EmptyMetadata lives in AlarmMetadataShared.swift — shared with the widget.)
//
// Schedules real system alarms via AlarmKit (iOS 26+). Alarms ring exactly like
// the built-in Clock app: full-screen on the Lock Screen, ring until dismissed,
// break through silent mode and Focus, and fire even when the app is killed.
//
// The system alarm screen shows two buttons:
//   • "Stop"   → StopAlarmIntent   → records history + starts Wake-Up Check
//   • "Drzemka" → SnoozeAlarmIntent → system countdown re-fires the alarm

final class AlarmKitManager: ObservableObject {

    static let shared = AlarmKitManager()

    /// True when the user denied the alarms permission — alarms cannot ring.
    @Published var permissionDenied = false

    private let reRingMapKey = "alarmkit_rering_ids"

    private init() {}

    // MARK: - Authorization

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let granted: Bool
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            granted = true
        case .notDetermined:
            do {
                granted = try await AlarmManager.shared.requestAuthorization() == .authorized
            } catch {
                // Typical cause: NSAlarmKitUsageDescription missing from Info.plist.
                print("❌ AlarmKit authorization request failed: \(error)")
                granted = false
            }
        case .denied:
            granted = false
        @unknown default:
            granted = false
        }
        await MainActor.run { self.permissionDenied = !granted }
        return granted
    }

    // MARK: - Scheduling

    func schedule(_ alarm: Alarm) async {
        guard alarm.isEnabled else { return }
        guard await requestAuthorizationIfNeeded() else { return }
        guard let schedule = makeSchedule(for: alarm) else { return }

        let title = alarm.label.isEmpty ? String(localized: "Alarm \(alarm.timeString)") : alarm.label
        let config = makeConfiguration(for: alarm, schedule: schedule,
                                       firingID: alarm.id, title: title)

        // Clear any stale alarm state under the same id first — a once-alarm
        // that already fired (and was ignored) lingers in AlarmKit, and
        // re-scheduling over it fails with the generic Code=0 error.
        try? await AlarmManager.shared.cancel(id: alarm.id)

        do {
            _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: config)
            print("✅ AlarmKit scheduled [\(alarm.id)] \(alarm.timeString)")
        } catch {
            print("""
            ❌ AlarmKit schedule failed [\(alarm.id)] \(alarm.timeString) \
            repeat=\(alarm.repeatSchedule.displayText) sound=\(alarm.soundName) \
            snooze=\(alarm.snoozeEnabled) wakeCheck=\(alarm.wakeUpCheckEnabled): \(error)
            """)
        }
    }

    func cancel(_ alarmID: UUID) {
        Task { try? await AlarmManager.shared.cancel(id: alarmID) }
        cancelReRing(for: alarmID)
    }

    // MARK: - Re-ring (Wake-Up Check escalation)

    /// Schedules a one-off AlarmKit alarm that fires if the user never responds
    /// to the Wake-Up Check notifications.
    func scheduleReRing(for alarm: Alarm, after seconds: TimeInterval) async {
        guard await requestAuthorizationIfNeeded() else { return }
        cancelReRing(for: alarm.id)

        let reRingID = UUID()
        saveReRingID(reRingID, for: alarm.id)

        let baseName = alarm.label.isEmpty ? String(localized: "Alarm") : alarm.label
        let title = String(localized: "\(baseName) — no response!")
        // Countdown timer instead of a fixed date: the system shows a live
        // ticking countdown until the re-ring fires.
        let config = makeConfiguration(for: alarm, schedule: nil,
                                       firingID: reRingID, title: title,
                                       preAlert: seconds)
        do {
            _ = try await AlarmManager.shared.schedule(id: reRingID, configuration: config)
            print("✅ AlarmKit re-ring in \(Int(seconds))s [\(reRingID)]")
        } catch {
            print("❌ AlarmKit re-ring failed: \(error)")
        }
    }

    func cancelReRing(for alarmID: UUID) {
        guard let reRingID = storedReRingID(for: alarmID) else { return }
        removeReRingID(for: alarmID)
        Task { try? await AlarmManager.shared.cancel(id: reRingID) }
    }

    /// Alarms whose wake-up check cycle is currently running (countdown ticking).
    func alarmIDsWithPendingReRing() -> [UUID] {
        let map = (UserDefaults.standard.dictionary(forKey: reRingMapKey) as? [String: String]) ?? [:]
        return map.keys.compactMap(UUID.init(uuidString:))
    }

    // MARK: - Configuration builders

    // Note: our own `Alarm` model shadows AlarmKit's `Alarm` type, so AlarmKit's
    // nested types must be written fully qualified (AlarmKit.Alarm.…).
    /// `preAlert` turns the alarm into a countdown timer: the system shows a
    /// live ticking countdown (Lock Screen / Dynamic Island) until it alerts.
    private func makeConfiguration(
        for alarm: Alarm,
        schedule: AlarmKit.Alarm.Schedule?,
        firingID: UUID,
        title: String,
        preAlert: TimeInterval? = nil
    ) -> AlarmManager.AlarmConfiguration<EmptyMetadata> {
        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.circle")

        // No-snooze alarms show only the Stop button on the system alarm screen.
        let alert: AlarmPresentation.Alert
        if alarm.snoozeEnabled {
            let snoozeButton = AlarmButton(
                text: "Snooze",
                textColor: .white,
                systemImageName: "moon.zzz.fill")
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stopButton,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stopButton)
        }

        let presentation: AlarmPresentation
        if preAlert != nil {
            let countdown = AlarmPresentation.Countdown(
                title: "Time left to confirm you're up",
                pauseButton: nil)
            presentation = AlarmPresentation(alert: alert, countdown: countdown)
        } else {
            presentation = AlarmPresentation(alert: alert)
        }

        let attributes = AlarmAttributes<EmptyMetadata>(
            presentation: presentation,
            tintColor: .orange)

        let postAlert: TimeInterval? = alarm.snoozeEnabled
            ? TimeInterval(alarm.snoozeDuration * 60)
            : nil
        let countdownDuration: AlarmKit.Alarm.CountdownDuration? =
            (preAlert == nil && postAlert == nil)
                ? nil
                : AlarmKit.Alarm.CountdownDuration(preAlert: preAlert, postAlert: postAlert)

        return AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: alarm.id.uuidString,
                                        firingID: firingID.uuidString),
            secondaryIntent: alarm.snoozeEnabled
                ? SnoozeAlarmIntent(alarmID: alarm.id.uuidString,
                                    firingID: firingID.uuidString)
                : nil,
            sound: soundFile(for: alarm).map { .named($0) } ?? .default)
    }

    /// File name of the custom tone, or nil for the system default sound.
    /// Volume is not configurable — alarms play at the system ringer volume.
    private func soundFile(for alarm: Alarm) -> String? {
        availableSounds.first(where: { $0.id == alarm.soundName })?.fileName
    }

    private func makeSchedule(for alarm: Alarm) -> AlarmKit.Alarm.Schedule? {
        switch alarm.repeatSchedule {
        case .once:
            guard let next = alarm.nextFireDate() else { return nil }
            return .fixed(next)
        case .weekdays(let days):
            let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
            let recurrence = AlarmKit.Alarm.Schedule.Relative.Recurrence.weekly(
                days.map(\.localeWeekday))
            return .relative(AlarmKit.Alarm.Schedule.Relative(time: time, repeats: recurrence))
        }
    }

    // MARK: - Re-ring ID persistence
    // The re-ring is a separate AlarmKit alarm with its own UUID; remember the
    // mapping so it can be cancelled when the user confirms they're awake.

    private func storedReRingID(for alarmID: UUID) -> UUID? {
        let map = UserDefaults.standard.dictionary(forKey: reRingMapKey) as? [String: String]
        guard let str = map?[alarmID.uuidString] else { return nil }
        return UUID(uuidString: str)
    }

    private func saveReRingID(_ id: UUID, for alarmID: UUID) {
        var map = (UserDefaults.standard.dictionary(forKey: reRingMapKey) as? [String: String]) ?? [:]
        map[alarmID.uuidString] = id.uuidString
        UserDefaults.standard.set(map, forKey: reRingMapKey)
    }

    private func removeReRingID(for alarmID: UUID) {
        var map = (UserDefaults.standard.dictionary(forKey: reRingMapKey) as? [String: String]) ?? [:]
        map.removeValue(forKey: alarmID.uuidString)
        UserDefaults.standard.set(map, forKey: reRingMapKey)
    }
}
