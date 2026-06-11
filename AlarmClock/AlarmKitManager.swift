import AlarmKit
import AppIntents
import SwiftUI

/// AlarmKit requires a metadata type for AlarmAttributes — we don't need any.
struct EmptyMetadata: AlarmMetadata {}

// MARK: - AlarmKitManager
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
        do {
            _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: config)
            print("✅ AlarmKit scheduled [\(alarm.id)] \(alarm.timeString)")
        } catch {
            print("❌ AlarmKit schedule failed: \(error)")
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
        let fireDate = Date().addingTimeInterval(seconds)
        let config = makeConfiguration(for: alarm, schedule: .fixed(fireDate),
                                       firingID: reRingID, title: title)
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

    // MARK: - Configuration builders

    // Note: our own `Alarm` model shadows AlarmKit's `Alarm` type, so AlarmKit's
    // nested types must be written fully qualified (AlarmKit.Alarm.…).
    private func makeConfiguration(
        for alarm: Alarm,
        schedule: AlarmKit.Alarm.Schedule,
        firingID: UUID,
        title: String
    ) -> AlarmManager.AlarmConfiguration<EmptyMetadata> {
        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.circle")
        let snoozeButton = AlarmButton(
            text: "Snooze",
            textColor: .white,
            systemImageName: "moon.zzz.fill")

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: snoozeButton,
            secondaryButtonBehavior: .custom)

        let attributes = AlarmAttributes<EmptyMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .orange)

        return AlarmManager.AlarmConfiguration(
            countdownDuration: AlarmKit.Alarm.CountdownDuration(
                preAlert: nil,
                postAlert: TimeInterval(alarm.snoozeDuration * 60)),
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: alarm.id.uuidString,
                                        firingID: firingID.uuidString),
            secondaryIntent: SnoozeAlarmIntent(alarmID: alarm.id.uuidString,
                                               firingID: firingID.uuidString),
            sound: .default)
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
