import SwiftUI
import UserNotifications

@main
struct AlarmApp: App {
    @StateObject private var store = AlarmStore()
    @StateObject private var historyStore = AlarmHistoryStore()
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var alarmKitManager = AlarmKitManager.shared

    init() {
        // Register wake-up check categories and clean up legacy notification alarms.
        NotificationManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(historyStore)
                .environmentObject(notificationManager)
                .environmentObject(alarmKitManager)
                .task {
                    await requestPermissionIfNeeded()
                    // Ask for the AlarmKit permission, then make sure every
                    // enabled alarm is scheduled as a real system alarm.
                    if await AlarmKitManager.shared.requestAuthorizationIfNeeded() {
                        AlarmScheduler.shared.rescheduleAll(from: store)
                    }
                }
        }
    }

    @MainActor
    private func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            notificationManager.requestPermission()
        }
    }
}
