import SwiftUI
import UserNotifications

@main
struct AlarmApp: App {
    @StateObject private var store = AlarmStore()
    @StateObject private var historyStore = AlarmHistoryStore()
    @StateObject private var alarmKitManager = AlarmKitManager.shared

    init() {
        // Synthesize the alarm tone files used by the sound picker and AlarmKit.
        AlarmToneGenerator.ensureSounds()
        cleanUpLegacyNotifications()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(historyStore)
                .environmentObject(alarmKitManager)
                .task {
                    // Ask for the AlarmKit permission, then make sure every
                    // enabled alarm is scheduled as a real system alarm.
                    if await AlarmKitManager.shared.requestAuthorizationIfNeeded() {
                        AlarmScheduler.shared.rescheduleAll(from: store)
                    }
                }
        }
    }

    /// The app no longer uses notifications at all — remove anything still
    /// pending from earlier versions (wake-up check reminders etc.).
    private func cleanUpLegacyNotifications() {
        let key = "notifications_removed_v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UserDefaults.standard.set(true, forKey: key)
    }
}
