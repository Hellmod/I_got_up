import Foundation

// MARK: - AlarmScheduler

/// Coordinates between AlarmStore and AlarmKitManager — single point of truth
/// for enabling/disabling alarms.
class AlarmScheduler {

    static let shared = AlarmScheduler()

    private init() {}

    /// Enable an alarm: schedule it in AlarmKit.
    func enable(_ alarm: Alarm) {
        Task { await AlarmKitManager.shared.schedule(alarm) }
    }

    /// Disable an alarm: cancel the AlarmKit alarm and any pending wake-up check.
    func disable(_ alarm: Alarm) {
        AlarmKitManager.shared.cancel(alarm.id)
        Task { await AlarmKitManager.shared.cancelWakeUpCheck(for: alarm.id) }
    }

    /// Toggle alarm on/off and update the store.
    func toggle(_ alarm: inout Alarm, in store: AlarmStore) {
        alarm.isEnabled.toggle()
        store.update(alarm)
        if alarm.isEnabled {
            enable(alarm)
        } else {
            disable(alarm)
        }
    }

    /// Call after adding a new alarm.
    func alarmAdded(_ alarm: Alarm, store: AlarmStore) {
        store.add(alarm)
        if alarm.isEnabled {
            enable(alarm)
        }
    }

    /// Call after editing an existing alarm.
    func alarmUpdated(_ alarm: Alarm, store: AlarmStore) {
        AlarmKitManager.shared.cancel(alarm.id) // remove old schedule
        store.update(alarm)
        if alarm.isEnabled {
            enable(alarm)
        }
    }

    /// Call when deleting an alarm.
    func alarmDeleted(_ alarm: Alarm, store: AlarmStore) {
        disable(alarm)
        store.delete(alarm)
    }

    /// Ensure all enabled alarms are scheduled in AlarmKit (e.g. on app launch).
    /// Scheduling with the same id overwrites, so this is safe to call repeatedly.
    /// Disabled alarms are left untouched so a pending wake-up check cycle for a
    /// just-fired once-alarm isn't cancelled by merely opening the app.
    func rescheduleAll(from store: AlarmStore) {
        // Schedule sequentially — concurrent schedule() calls right after launch
        // can race the AlarmKit daemon and fail with a generic Code=0 error.
        let enabled = store.alarms.filter(\.isEnabled)
        Task {
            for alarm in enabled {
                await AlarmKitManager.shared.schedule(alarm)
            }
        }
    }
}
