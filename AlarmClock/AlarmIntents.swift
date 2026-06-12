import AlarmKit
import AppIntents
import Foundation

// MARK: - StopAlarmIntent
//
// Runs when the user taps "Stop" on the system alarm screen. The system
// launches the app in the background to perform it — works from killed state.
//
// alarmID  = the Alarm in our store (business logic)
// firingID = the AlarmKit alarm that is ringing (main alarm or re-ring)

struct StopAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop alarm"

    @Parameter(title: "alarmID") var alarmID: String
    @Parameter(title: "firingID") var firingID: String

    init() {}

    init(alarmID: String, firingID: String) {
        self.alarmID = alarmID
        self.firingID = firingID
    }

    func perform() async throws -> some IntentResult {
        if let firing = UUID(uuidString: firingID) {
            try? await AlarmManager.shared.stop(id: firing)
        }
        guard let id = UUID(uuidString: alarmID) else { return .result() }

        let store = AlarmStore()
        guard let alarm = store.alarms.first(where: { $0.id == id }) else {
            return .result()
        }

        AlarmHistoryStore().record(alarm: alarm, action: .dismissed)

        // One-time alarms must not ring again tomorrow. Only for the main alarm —
        // a re-ring of a once-alarm means it was already disabled at first stop.
        if firingID == alarmID, case .once = alarm.repeatSchedule, alarm.isEnabled {
            var updated = alarm
            updated.isEnabled = false
            store.update(updated)
        }

        // A fired snooze ring leaves bookkeeping behind — clear it.
        AlarmKitManager.shared.cancelSnoozeRing(for: id)

        // Stopping the alarm starts the wake-up verification cycle:
        // delay phase, response window, then an AlarmKit re-ring if no response.
        await AlarmKitManager.shared.startWakeUpCheck(for: alarm)

        return .result()
    }
}

// MARK: - SnoozeAlarmIntent
//
// Runs when the user taps the snooze button on the system alarm screen.
// Swipe-proof: instead of the system countdown (whose Live Activity can be
// swiped away, cancelling the re-fire), it stops the ringing alarm and
// schedules our own fixed-date snooze ring plus a cosmetic countdown.

struct SnoozeAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze"

    @Parameter(title: "alarmID") var alarmID: String
    @Parameter(title: "firingID") var firingID: String

    init() {}

    init(alarmID: String, firingID: String) {
        self.alarmID = alarmID
        self.firingID = firingID
    }

    func perform() async throws -> some IntentResult {
        if let firing = UUID(uuidString: firingID) {
            try? await AlarmManager.shared.stop(id: firing)
        }
        guard let id = UUID(uuidString: alarmID) else { return .result() }

        let store = AlarmStore()
        guard let alarm = store.alarms.first(where: { $0.id == id }) else {
            return .result()
        }

        AlarmHistoryStore().record(alarm: alarm, action: .snoozed,
                                   detail: String(localized: "\(alarm.snoozeDuration) min"))

        // One-time alarms: the original occurrence is consumed by snoozing —
        // the snooze chain continues through its own fixed-date alarm.
        if firingID == alarmID, case .once = alarm.repeatSchedule, alarm.isEnabled {
            var updated = alarm
            updated.isEnabled = false
            store.update(updated)
        }

        // Snoozing means the user is not up yet — any pending wake-up check is
        // stale; a fresh cycle starts when they eventually stop the alarm.
        AlarmKitManager.shared.cancelWakeUpCheck(for: id)

        await AlarmKitManager.shared.scheduleSnoozeRing(for: alarm)

        return .result()
    }
}
