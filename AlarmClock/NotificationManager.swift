import Foundation
import UserNotifications

// MARK: - Notification identifiers

enum NotificationCategory {
    static let wakeUpCheck = "WAKEUP_CHECK_CATEGORY"
}

enum NotificationAction {
    static let wakeConfirm = "WAKE_CONFIRM_ACTION"
    static let wakeSnooze = "WAKE_SNOOZE_ACTION"
}

// MARK: - NotificationManager
//
// Since the AlarmKit rewrite, notifications are used ONLY for the Wake-Up Check
// reminders. The alarms themselves — including the no-response re-ring — are
// real AlarmKit alarms handled by AlarmKitManager.

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    @Published var permissionGranted: Bool = false
    @Published var permissionDenied: Bool = false
    /// Set when the user taps a Wake-Up Check notification body —
    /// ContentView presents WakeUpCheckView full-screen.
    @Published var pendingWakeUpAlarm: Alarm?

    /// Upper bound used when sweeping reminder IDs during cancellation.
    private let maxWakeUpReminders = 30

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Setup

    func setup() {
        migrateFromNotificationAlarms()
        registerCategories()
        checkPermission()
    }

    /// One-time cleanup after the AlarmKit rewrite: earlier versions scheduled
    /// repeating UNNotifications as the alarm mechanism — remove them all so
    /// stale "Budzik" banners don't keep firing alongside AlarmKit alarms.
    private func migrateFromNotificationAlarms() {
        let key = "migrated_to_alarmkit_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UserDefaults.standard.set(true, forKey: key)
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                self?.permissionDenied = !granted
            }
        }
    }

    private func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                let granted = settings.authorizationStatus == .authorized ||
                              settings.authorizationStatus == .provisional
                self?.permissionGranted = granted
                self?.permissionDenied = settings.authorizationStatus == .denied
            }
        }
    }

    // MARK: - Category registration

    private func registerCategories() {
        let confirmAction = UNNotificationAction(
            identifier: NotificationAction.wakeConfirm,
            title: "✅ Tak, wstałem",
            options: [.foreground]
        )
        let wakeSnoozeAction = UNNotificationAction(
            identifier: NotificationAction.wakeSnooze,
            title: "😴 Jeszcze nie",
            options: []
        )
        let wakeUpCategory = UNNotificationCategory(
            identifier: NotificationCategory.wakeUpCheck,
            actions: [confirmAction, wakeSnoozeAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([wakeUpCategory])
    }

    // MARK: - Wake-Up Check

    /// Starts the verification cycle after an alarm is stopped:
    /// reminder notifications every minute for `wakeUpNoResponseTime` minutes
    /// (starting after `wakeUpCheckDelay`), then a real AlarmKit re-ring.
    func scheduleWakeUpCheck(for alarm: Alarm) {
        guard alarm.wakeUpCheckEnabled else { return }

        let initialDelay = TimeInterval(alarm.wakeUpCheckDelay * 60)
        let count = max(1, alarm.wakeUpNoResponseTime)

        for i in 0..<count {
            let content = UNMutableNotificationContent()
            if i == 0 {
                content.title = "Hej, czy już wstajesz? 👋"
            } else if i == count - 1 {
                content.title = "Ostatnie przypomnienie! ⚠️ (\(i + 1)/\(count))"
            } else {
                content.title = "Wstawaj! 👋 (\(i + 1)/\(count))"
            }
            content.body = "Potwierdź że wstałeś — lub alarm zaraz zadzwoni ponownie."
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.wakeUpCheck
            content.userInfo = ["alarmID": alarm.id.uuidString]
            content.interruptionLevel = .timeSensitive

            schedule(identifier: wakeUpCheckID(alarm.id, index: i),
                     content: content,
                     trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: initialDelay + TimeInterval(i * 60),
                        repeats: false))
        }

        // No response after the last reminder → a real alarm rings again.
        let ringDelay = initialDelay + TimeInterval(count * 60)
        Task { await AlarmKitManager.shared.scheduleReRing(for: alarm, after: ringDelay) }
    }

    func cancelWakeUpCheck(for alarmID: UUID) {
        var ids: [String] = []
        for i in 0..<maxWakeUpReminders {
            ids.append(wakeUpCheckID(alarmID, index: i))
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        AlarmKitManager.shared.cancelReRing(for: alarmID)
    }

    private func wakeUpCheckID(_ alarmID: UUID, index: Int) -> String {
        "wakeup_\(alarmID)_\(index)"
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let alarmIDStr = userInfo["alarmID"] as? String,
              let alarmID = UUID(uuidString: alarmIDStr) else {
            completionHandler(); return
        }

        let store = AlarmStore()
        guard let alarm = store.alarms.first(where: { $0.id == alarmID }) else {
            completionHandler(); return
        }

        let historyStore = AlarmHistoryStore()

        switch response.actionIdentifier {

        // Tap on the notification body — open the in-app confirmation screen
        // (the long-press actions below remain available too).
        case UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == NotificationCategory.wakeUpCheck {
                DispatchQueue.main.async { self.pendingWakeUpAlarm = alarm }
            }

        case NotificationAction.wakeConfirm:
            historyStore.record(alarm: alarm, action: .wakeConfirmed)
            cancelWakeUpCheck(for: alarmID)

        case NotificationAction.wakeSnooze:
            historyStore.record(alarm: alarm, action: .wakePostponed)
            cancelWakeUpCheck(for: alarmID)
            // "Not up yet" → ring again (real alarm) in 5 minutes.
            Task { await AlarmKitManager.shared.scheduleReRing(for: alarm, after: 5 * 60) }

        default:
            break
        }

        completionHandler()
    }

    // MARK: - Helpers

    private func schedule(
        identifier: String,
        content: UNMutableNotificationContent,
        trigger: UNNotificationTrigger
    ) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Notification FAILED [\(identifier)]: \(error)")
            } else {
                print("✅ Notification scheduled OK [\(identifier)]")
            }
        }
    }

    // MARK: - Debug

    func listPendingNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            print("📋 Pending notifications (\(requests.count)):")
            for r in requests {
                if let t = r.trigger as? UNCalendarNotificationTrigger {
                    print("  • \(r.identifier) → \(t.dateComponents)")
                } else if let t = r.trigger as? UNTimeIntervalNotificationTrigger {
                    print("  • \(r.identifier) → in \(Int(t.timeInterval))s")
                }
            }
        }
    }
}
