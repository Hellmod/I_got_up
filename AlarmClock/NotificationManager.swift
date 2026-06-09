import Foundation
import UserNotifications

// MARK: - Notification identifiers

enum NotificationID {
    static func alarm(for id: UUID) -> String { "alarm_\(id)" }
    static func wakeUpCheck(for id: UUID) -> String { "wakeup_\(id)" }
    static func snooze(for id: UUID) -> String { "snooze_\(id)" }
    static func noResponseRing(for id: UUID) -> String { "noresp_\(id)" }
    static func backup(for id: UUID, index: Int) -> String { "alarm_\(id)_b\(index)" }
}

enum NotificationCategory {
    static let alarm = "ALARM_CATEGORY"
    static let wakeUpCheck = "WAKEUP_CHECK_CATEGORY"
}

enum NotificationAction {
    static let dismiss = "DISMISS_ACTION"
    static let snooze5 = "SNOOZE_5_ACTION"
    static let snooze10 = "SNOOZE_10_ACTION"
    static let wakeConfirm = "WAKE_CONFIRM_ACTION"
    static let wakeSnooze = "WAKE_SNOOZE_ACTION"
}

// MARK: - NotificationManager

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    @Published var permissionGranted: Bool = false
    @Published var permissionDenied: Bool = false
    /// Set when an alarm fires while the app is in the foreground — triggers in-app alarm UI.
    @Published var firingAlarm: Alarm?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Setup

    func setup() {
        registerCategories()
        checkPermission()
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
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss,
            title: "Wyłącz alarm",
            options: [.destructive]
        )
        let snooze5Action = UNNotificationAction(
            identifier: NotificationAction.snooze5,
            title: "Drzemka 5 min",
            options: []
        )
        let snooze10Action = UNNotificationAction(
            identifier: NotificationAction.snooze10,
            title: "Drzemka 10 min",
            options: []
        )
        let alarmCategory = UNNotificationCategory(
            identifier: NotificationCategory.alarm,
            actions: [dismissAction, snooze5Action, snooze10Action],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

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

        UNUserNotificationCenter.current().setNotificationCategories([alarmCategory, wakeUpCategory])
    }

    // MARK: - Schedule alarm

    func scheduleAlarm(_ alarm: Alarm) {
        guard alarm.isEnabled else { return }

        switch alarm.repeatSchedule {
        case .once:
            let comps = components(hour: alarm.hour, minute: alarm.minute)
            scheduleSet(alarm: alarm, base: comps, suffix: "", repeats: false)

        case .weekdays(let days):
            cancelAlarm(alarm)
            for day in days {
                var comps = components(hour: alarm.hour, minute: alarm.minute)
                comps.weekday = day.calendarWeekday
                scheduleSet(alarm: alarm, base: comps, suffix: "_\(day.rawValue)", repeats: true)
            }
        }
    }

    // Schedules main + 2 backup notifications so the alarm "rings" multiple times.
    private func scheduleSet(alarm: Alarm, base: DateComponents, suffix: String, repeats: Bool) {
        let baseID = NotificationID.alarm(for: alarm.id) + suffix
        schedule(identifier: baseID,
                 content: makeAlarmContent(alarm),
                 trigger: UNCalendarNotificationTrigger(dateMatching: base, repeats: repeats))

        // Backup rings at +1 min and +2 min (only for non-repeating .once alarms to avoid clutter)
        guard !repeats else { return }
        for i in 1...2 {
            let backupContent = makeAlarmContent(alarm)
            backupContent.subtitle = "Ponawianie \(i)/2"
            let backupComps = addMinutes(to: base, count: i)
            schedule(identifier: "\(baseID)_b\(i)",
                     content: backupContent,
                     trigger: UNCalendarNotificationTrigger(dateMatching: backupComps, repeats: false))
        }
    }

    // MARK: - Cancel

    func cancelAlarm(_ alarm: Alarm) {
        var ids: [String] = []
        let base = NotificationID.alarm(for: alarm.id)
        // Once + backups
        ids += [base, "\(base)_b1", "\(base)_b2"]
        // Weekday repeats
        for day in Weekday.allCases {
            ids.append("\(base)_\(day.rawValue)")
        }
        // Supporting notifications
        ids += [NotificationID.wakeUpCheck(for: alarm.id),
                NotificationID.snooze(for: alarm.id),
                NotificationID.noResponseRing(for: alarm.id)]

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    func cancelAlarmBackups(for alarmID: UUID) {
        let base = NotificationID.alarm(for: alarmID)
        let ids = ["\(base)_b1", "\(base)_b2"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func cancelWakeUpCheck(for alarmID: UUID) {
        let ids = [NotificationID.wakeUpCheck(for: alarmID),
                   NotificationID.noResponseRing(for: alarmID)]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Wake-Up Check

    func scheduleWakeUpCheck(for alarm: Alarm) {
        guard alarm.wakeUpCheckEnabled else { return }

        let delay = TimeInterval(alarm.wakeUpCheckDelay * 60)

        let checkContent = UNMutableNotificationContent()
        checkContent.title = "Hej, czy już wstajesz? 👋"
        checkContent.body = "Potwierdź, że wstałeś z łóżka!"
        checkContent.sound = .default
        checkContent.categoryIdentifier = NotificationCategory.wakeUpCheck
        checkContent.userInfo = ["alarmID": alarm.id.uuidString]
        if #available(iOS 15.0, *) { checkContent.interruptionLevel = .timeSensitive }

        schedule(identifier: NotificationID.wakeUpCheck(for: alarm.id),
                 content: checkContent,
                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))

        // If no response within 3 minutes after the check, ring again.
        let noResponseDelay = delay + 3 * 60
        let ringContent = makeAlarmContent(alarm)
        ringContent.title = "Budzik — brak odpowiedzi!"
        ringContent.body = "Nie potwierdziłeś wstania. Czas wstawać! ⏰"
        schedule(identifier: NotificationID.noResponseRing(for: alarm.id),
                 content: ringContent,
                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: noResponseDelay, repeats: false))
    }

    // MARK: - Snooze

    func scheduleSnooze(for alarm: Alarm, minutes: Int) {
        let delay = TimeInterval(minutes * 60)
        let content = makeAlarmContent(alarm)
        content.title = "Budzik (drzemka) ⏰"
        schedule(identifier: NotificationID.snooze(for: alarm.id),
                 content: content,
                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))

        guard alarm.wakeUpCheckEnabled else { return }
        let checkDelay = delay + TimeInterval(alarm.wakeUpCheckDelay * 60)
        let checkContent = UNMutableNotificationContent()
        checkContent.title = "Hej, czy już wstajesz? 👋"
        checkContent.body = "Twoja drzemka minęła — czy wstałeś?"
        checkContent.sound = .default
        checkContent.categoryIdentifier = NotificationCategory.wakeUpCheck
        checkContent.userInfo = ["alarmID": alarm.id.uuidString]
        if #available(iOS 15.0, *) { checkContent.interruptionLevel = .timeSensitive }
        schedule(identifier: NotificationID.wakeUpCheck(for: alarm.id),
                 content: checkContent,
                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: checkDelay, repeats: false))
    }

    func scheduleReRing(for alarm: Alarm) {
        let delay: TimeInterval = 5 * 60
        let content = makeAlarmContent(alarm)
        content.title = "Budzik znowu dzwoni ⏰"
        content.body = "Powiedziałeś że jeszcze nie wstajesz…"
        schedule(identifier: NotificationID.snooze(for: alarm.id),
                 content: content,
                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))

        guard alarm.wakeUpCheckEnabled else { return }
        let checkDelay = delay + TimeInterval(alarm.wakeUpCheckDelay * 60)
        let checkContent = UNMutableNotificationContent()
        checkContent.title = "Hej, czy już wstajesz? 👋"
        checkContent.body = "Potwierdź, że tym razem wstałeś!"
        checkContent.sound = .default
        checkContent.categoryIdentifier = NotificationCategory.wakeUpCheck
        checkContent.userInfo = ["alarmID": alarm.id.uuidString]
        if #available(iOS 15.0, *) { checkContent.interruptionLevel = .timeSensitive }
        schedule(identifier: NotificationID.wakeUpCheck(for: alarm.id),
                 content: checkContent,
                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: checkDelay, repeats: false))
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content

        // If an alarm fires while the app is in the foreground, show in-app UI instead of banner.
        if content.categoryIdentifier == NotificationCategory.alarm,
           let alarmIDStr = content.userInfo["alarmID"] as? String,
           let alarmID = UUID(uuidString: alarmIDStr) {
            cancelAlarmBackups(for: alarmID)
            let store = AlarmStore()
            if let alarm = store.alarms.first(where: { $0.id == alarmID }) {
                DispatchQueue.main.async { self.firingAlarm = alarm }
            }
            // Play sound but skip banner — the full-screen view takes over.
            completionHandler([.sound])
        } else {
            completionHandler([.banner, .sound, .badge])
        }
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

        cancelAlarmBackups(for: alarmID)

        let store = AlarmStore()
        guard let alarm = store.alarms.first(where: { $0.id == alarmID }) else {
            completionHandler(); return
        }

        switch response.actionIdentifier {

        // User tapped notification body (app was in background/killed) — show in-app UI.
        case UNNotificationDefaultActionIdentifier:
            if response.notification.request.content.categoryIdentifier == NotificationCategory.alarm {
                DispatchQueue.main.async { self.firingAlarm = alarm }
            }
            // Schedule wake-up check in case user doesn't interact with the in-app view.
            cancelWakeUpCheck(for: alarmID)
            scheduleWakeUpCheck(for: alarm)

        case NotificationAction.dismiss:
            cancelWakeUpCheck(for: alarmID)
            scheduleWakeUpCheck(for: alarm)

        case NotificationAction.snooze5:
            cancelWakeUpCheck(for: alarmID)
            scheduleSnooze(for: alarm, minutes: 5)

        case NotificationAction.snooze10:
            cancelWakeUpCheck(for: alarmID)
            scheduleSnooze(for: alarm, minutes: 10)

        case NotificationAction.wakeConfirm:
            cancelWakeUpCheck(for: alarmID)

        case NotificationAction.wakeSnooze:
            cancelWakeUpCheck(for: alarmID)
            scheduleReRing(for: alarm)

        default:
            break
        }

        completionHandler()
    }

    // MARK: - Helpers

    private func makeAlarmContent(_ alarm: Alarm) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Budzik ⏰" : alarm.label
        content.body = "Czas wstawać! \(alarm.timeString)"
        content.categoryIdentifier = NotificationCategory.alarm
        content.userInfo = ["alarmID": alarm.id.uuidString]
        content.sound = .default
        if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
        return content
    }

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

    private func components(hour: Int, minute: Int) -> DateComponents {
        var c = DateComponents()
        c.hour = hour
        c.minute = minute
        c.second = 0
        return c
    }

    private func addMinutes(to base: DateComponents, count: Int) -> DateComponents {
        var c = base
        let total = (c.minute ?? 0) + count
        c.minute = total % 60
        if total >= 60 { c.hour = ((c.hour ?? 0) + 1) % 24 }
        return c
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
