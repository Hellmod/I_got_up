import SwiftUI
import UserNotifications

@main
struct AlarmApp: App {
    @StateObject private var store = AlarmStore()
    @StateObject private var historyStore = AlarmHistoryStore()
    @StateObject private var notificationManager = NotificationManager.shared

    init() {
        NotificationManager.shared.setup()
        // Generate the custom 29-second alarm tone used by UNNotificationSound.
        // No-op if the file already exists from a previous launch.
        AlarmSoundGenerator.ensureAlarmSound()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(historyStore)
                .environmentObject(notificationManager)
                .task {
                    await requestPermissionIfNeeded()
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
