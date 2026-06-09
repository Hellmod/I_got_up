import CallKit
import Foundation

// MARK: - AlarmCallManager
//
// Uses CXProvider to show an iOS "incoming call" screen when an alarm fires.
// Advantages over UNNotificationSound:
//  • Full-screen alarm UI even when the app is minimised
//  • Rings with the default ringtone (CAN bypass silent mode per iOS policy)
//  • User taps "Accept" → app opens → AlarmActiveView shown
//  • User taps "Decline" → alarm dismissed without opening app
//
// Limitation: only works when the app is running in the background (not killed).
// For the killed state the 29-second UNNotificationSound remains the fallback.

final class AlarmCallManager: NSObject, CXProviderDelegate {
    static let shared = AlarmCallManager()

    private let provider: CXProvider
    private var activeCallUUID: UUID?
    private var activeAlarm: Alarm?

    private override init() {
        let config = CXProviderConfiguration(localizedName: "Budzik")
        config.supportsVideo  = false
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        // nil → system default ringtone (loud, bypasses ringer)
        config.ringtoneSound  = AlarmSoundGenerator.soundName

        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    // MARK: - Public

    func reportIncomingAlarm(_ alarm: Alarm) {
        // Cancel any stale call first
        if let old = activeCallUUID {
            provider.reportCall(with: old, endedAt: Date(), reason: .remoteEnded)
        }

        let uuid = UUID()
        activeCallUUID = uuid
        activeAlarm    = alarm

        let update = CXCallUpdate()
        update.localizedCallerName = alarm.label.isEmpty
            ? "Budzik \(alarm.timeString)"
            : "\(alarm.label)  \(alarm.timeString)"
        update.remoteHandle    = CXHandle(type: .generic, value: alarm.timeString)
        update.hasVideo        = false
        update.supportsHolding = false
        update.supportsGrouping   = false
        update.supportsUngrouping = false

        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error = error {
                print("❌ AlarmCallManager: \(error.localizedDescription)")
            }
        }
    }

    /// Call when the user dismisses or snoozes the alarm inside the app.
    func endActiveCall() {
        guard let uuid = activeCallUUID else { return }
        provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        activeCallUUID = nil
        activeAlarm    = nil
    }

    // MARK: - CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        activeCallUUID = nil
        activeAlarm    = nil
    }

    /// User tapped "Accept" on the call screen → open app and show AlarmActiveView.
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        if let alarm = activeAlarm {
            DispatchQueue.main.async {
                NotificationManager.shared.firingAlarm = alarm
            }
        }
        action.fulfill()
    }

    /// User tapped "Decline" on the call screen → dismiss alarm silently.
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let alarmID = activeAlarm?.id
        activeCallUUID = nil
        activeAlarm    = nil
        DispatchQueue.main.async {
            if let id = alarmID, NotificationManager.shared.firingAlarm?.id == id {
                NotificationManager.shared.firingAlarm = nil
            }
        }
        action.fulfill()
    }
}
