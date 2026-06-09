import SwiftUI
import UserNotifications

@main
struct AlarmApp: App {
    @StateObject private var store = AlarmStore()
    @StateObject private var notificationManager = NotificationManager.shared

    init() {
        // Register notification categories and check permission status before UI appears
        NotificationManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
