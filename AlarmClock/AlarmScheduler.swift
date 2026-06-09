import Foundation
import UserNotifications

// MARK: - AlarmScheduler

/// Coordinates between AlarmStore and NotificationManager — single point of truth
/// for enabling/disabling alarms.
class AlarmScheduler {

    static let shared = AlarmScheduler()
    private let nm = NotificationManager.shared

    private init() {}

    /// Enable an alarm: schedule its notification(s).
    func enable(_ alarm: Alarm) {
        nm.scheduleAlarm(alarm)
    }

    /// Disable an alarm: cancel all pending notifications for it.
    func disable(_ alarm: Alarm) {
        nm.cancelAlarm(alarm)
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
        disable(alarm) // remove old schedule
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

    /// Re-schedule all enabled alarms (e.g. on app launch after notification permission granted).
    func rescheduleAll(from store: AlarmStore) {
        for alarm in store.alarms {
            disable(alarm)
            if alarm.isEnabled {
                enable(alarm)
            }
        }
    }

    // MARK: - Debug helpers

    func listPending(completion: @escaping ([UNNotificationRequest]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests(completionHandler: completion)
    }
}
