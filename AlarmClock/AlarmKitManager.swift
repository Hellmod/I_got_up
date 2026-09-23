import AlarmKit
import AppIntents
import SwiftUI

// MARK: - WakeCheckState

/// Persisted phases of a running wake-up check cycle.
struct WakeCheckState: Codable {
    var alarmID: UUID
    var delayEnd: Date   // phase 1 ends: until then confirmation is locked
    var ringDate: Date   // phase 2 ends: the re-ring alarm fires
}

/// A pending swipe-proof snooze ring.
struct SnoozeState: Codable {
    var alarmID: UUID
    var ringDate: Date
}

// MARK: - AlarmKitManager
// (EmptyMetadata lives in AlarmMetadataShared.swift — shared with the widget.)
//
// Schedules real system alarms via AlarmKit (iOS 26+). Alarms ring exactly like
// the built-in Clock app: full-screen on the Lock Screen, ring until dismissed,
// break through silent mode and Focus, and fire even when the app is killed.
//
// The system alarm screen shows two buttons:
//   • "Stop"   → StopAlarmIntent   → records history + starts Wake-Up Check
//   • "Drzemka" → SnoozeAlarmIntent → system countdown re-fires the alarm

final class AlarmKitManager: ObservableObject {

    static let shared = AlarmKitManager()

    /// True when the user denied the alarms permission — alarms cannot ring.
    @Published var permissionDenied = false
    /// Set when the wake-up confirmation screen should be presented.
    @Published var pendingWakeUpAlarm: Alarm?
    /// Running cycles, mirrored from UserDefaults for the in-app countdown list.
    @Published var activeWakeChecks: [WakeCheckState] = []
    @Published var activeSnoozes: [SnoozeState] = []

    private let reRingMapKey = "alarmkit_rering_ids"
    private let backupMapKey = "alarmkit_backup_ids"
    private let snoozeMapKey = "alarmkit_snooze_ids"
    private let wakeCheckStatesKey = "wake_check_states_v1"
    private let snoozeStatesKey = "snooze_states_v1"

    /// Seconds the swipe-proof backup re-ring fires AFTER the visible countdown.
    /// Two AlarmKit alarms at the exact same instant are non-deterministic (one
    /// can be dropped), so the backup is offset. It's also the window in which
    /// stopping the visible re-ring cancels the backup, avoiding a double ring.
    private let reRingBackupGrace: TimeInterval = 30

    private init() {
        refreshActiveCycles()
    }

    /// Re-reads cycle state from UserDefaults (intents may have written it
    /// from a background launch) and publishes it for the in-app list.
    func refreshActiveCycles() {
        let now = Date()
        let wake = loadWakeCheckStates().filter { $0.ringDate > now }
        let snooze = loadSnoozeStates().filter { $0.ringDate > now }
        DispatchQueue.main.async {
            self.activeWakeChecks = wake
            self.activeSnoozes = snooze
        }
    }

    // MARK: - Authorization

    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let granted: Bool
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            granted = true
        case .notDetermined:
            do {
                granted = try await AlarmManager.shared.requestAuthorization() == .authorized
            } catch {
                // Typical cause: NSAlarmKitUsageDescription missing from Info.plist.
                print("❌ AlarmKit authorization request failed: \(error)")
                granted = false
            }
        case .denied:
            granted = false
        @unknown default:
            granted = false
        }
        await MainActor.run { self.permissionDenied = !granted }
        return granted
    }

    // MARK: - Scheduling

    func schedule(_ alarm: Alarm) async {
        guard alarm.isEnabled else { return }
        guard await requestAuthorizationIfNeeded() else { return }
        guard let schedule = makeSchedule(for: alarm) else { return }

        let title = alarm.label.isEmpty ? String(localized: "Alarm \(alarm.timeString)") : alarm.label
        let config = makeConfiguration(for: alarm, schedule: schedule,
                                       firingID: alarm.id, title: title)

        // Clear any stale alarm state under the same id first — a once-alarm
        // that already fired (and was ignored) lingers in AlarmKit, and
        // re-scheduling over it fails with the generic Code=0 error.
        try? await AlarmManager.shared.cancel(id: alarm.id)

        do {
            _ = try await AlarmManager.shared.schedule(id: alarm.id, configuration: config)
            print("✅ AlarmKit scheduled [\(alarm.id)] \(alarm.timeString)")
        } catch {
            print("""
            ❌ AlarmKit schedule failed [\(alarm.id)] \(alarm.timeString) \
            repeat=\(alarm.repeatSchedule.displayText) sound=\(alarm.soundName) \
            snooze=\(alarm.snoozeEnabled) wakeCheck=\(alarm.wakeUpCheckEnabled): \(error)
            """)
        }
    }

    func cancel(_ alarmID: UUID) {
        Task {
            try? await AlarmManager.shared.cancel(id: alarmID)
            await cancelReRing(for: alarmID)
            await cancelSnoozeRing(for: alarmID)
        }
    }

    // MARK: - Snooze ring (swipe-proof)

    /// Schedules the snooze re-ring as its own AlarmKit countdown timer. Because
    /// it's a separate id (not the main alarm transitioned to countdown), the
    /// system-rendered countdown — visible on the Lock Screen even when locked —
    /// and any swipe-to-cancel only affect the snooze, never the repeating alarm.
    func scheduleSnoozeRing(for alarm: Alarm) async {
        guard await requestAuthorizationIfNeeded() else { return }
        await cancelSnoozeRing(for: alarm.id)

        let snoozeSeconds = TimeInterval(alarm.snoozeDuration * 60)
        let ringDate = Date().addingTimeInterval(snoozeSeconds)
        let title = alarm.label.isEmpty ? String(localized: "Alarm \(alarm.timeString)") : alarm.label

        // schedule: nil + countdownPreAlert → a system countdown timer that the
        // OS draws and re-rings on its own, reliably, even from the Lock Screen.
        let snoozeID = UUID()
        saveID(snoozeID, for: alarm.id, in: snoozeMapKey)
        let config = makeConfiguration(for: alarm, schedule: nil,
                                       firingID: snoozeID, title: title,
                                       countdownPreAlert: snoozeSeconds)
        do {
            _ = try await AlarmManager.shared.schedule(id: snoozeID, configuration: config)
            print("✅ AlarmKit snooze countdown \(alarm.snoozeDuration)min [\(snoozeID)]")
        } catch {
            print("❌ AlarmKit snooze ring failed: \(error)")
        }

        var states = loadSnoozeStates().filter { $0.alarmID != alarm.id }
        states.append(SnoozeState(alarmID: alarm.id, ringDate: ringDate))
        saveSnoozeStates(states)
        refreshActiveCycles()
    }

    func cancelSnoozeRing(for alarmID: UUID) async {
        if let id = storedID(for: alarmID, in: snoozeMapKey) {
            removeID(for: alarmID, in: snoozeMapKey)
            try? await AlarmManager.shared.cancel(id: id)
        }
        saveSnoozeStates(loadSnoozeStates().filter { $0.alarmID != alarmID })
        refreshActiveCycles()
    }

    private func loadSnoozeStates() -> [SnoozeState] {
        guard let data = UserDefaults.standard.data(forKey: snoozeStatesKey),
              let states = try? JSONDecoder().decode([SnoozeState].self, from: data) else { return [] }
        return states
    }

    private func saveSnoozeStates(_ states: [SnoozeState]) {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: snoozeStatesKey)
        }
    }

    // MARK: - Re-ring (Wake-Up Check escalation)

    /// Re-rings the alarm if the user never confirms they're up. Two alarms:
    ///   • a NATIVE AlarmKit countdown timer the system draws on the Lock Screen
    ///     (visible even when locked), firing at `seconds`;
    ///   • a swipe-proof fixed-date backup `reRingBackupGrace` seconds later, so
    ///     even if the visible countdown is swiped away (which cancels it) the
    ///     wake-up check still can't be silently dismissed.
    /// Stopping the visible re-ring cancels the backup (see cancelReRing), so a
    /// double ring only happens if the user neither responds nor stops in time.
    func scheduleReRing(for alarm: Alarm, after seconds: TimeInterval) async {
        guard await requestAuthorizationIfNeeded() else { return }
        await cancelReRing(for: alarm.id)

        let baseName = alarm.label.isEmpty ? String(localized: "Alarm") : alarm.label
        let title = String(localized: "\(baseName) — no response!")

        // Visible countdown: a native timer (schedule: nil + preAlert). The OS
        // renders the ticking countdown and re-rings on its own, even locked.
        let reRingID = UUID()
        saveID(reRingID, for: alarm.id, in: reRingMapKey)
        let config = makeConfiguration(for: alarm, schedule: nil,
                                       firingID: reRingID, title: title,
                                       countdownPreAlert: seconds)
        do {
            _ = try await AlarmManager.shared.schedule(id: reRingID, configuration: config)
            print("✅ AlarmKit re-ring countdown +\(Int(seconds))s [\(reRingID)]")
        } catch {
            print("❌ AlarmKit re-ring failed: \(error)")
        }

        // Swipe-proof backup: a plain fixed-date alarm shortly after. Offset
        // because two AlarmKit alarms at the same instant are non-deterministic.
        let backupID = UUID()
        saveID(backupID, for: alarm.id, in: backupMapKey)
        let backupConfig = makeConfiguration(
            for: alarm,
            schedule: .fixed(Date().addingTimeInterval(seconds + reRingBackupGrace)),
            firingID: backupID, title: title)
        do {
            _ = try await AlarmManager.shared.schedule(id: backupID, configuration: backupConfig)
            print("✅ AlarmKit backup re-ring +\(Int(seconds + reRingBackupGrace))s [\(backupID)]")
        } catch {
            print("❌ AlarmKit backup re-ring failed: \(error)")
        }
    }

    func cancelReRing(for alarmID: UUID) async {
        for mapKey in [reRingMapKey, backupMapKey] {
            if let id = storedID(for: alarmID, in: mapKey) {
                removeID(for: alarmID, in: mapKey)
                try? await AlarmManager.shared.cancel(id: id)
            }
        }
    }

    /// Alarms whose wake-up check cycle is currently running (countdown ticking).
    func alarmIDsWithPendingReRing() -> [UUID] {
        let map = (UserDefaults.standard.dictionary(forKey: reRingMapKey) as? [String: String]) ?? [:]
        return map.keys.compactMap(UUID.init(uuidString:))
    }

    // MARK: - Wake-Up Check cycle
    // Notification-free: a delay phase (confirmation locked), then a response
    // window, then the AlarmKit re-ring fires. The in-app WakeUpCheckView reads
    // WakeCheckState to render both countdown timers.

    func startWakeUpCheck(for alarm: Alarm) async {
        guard alarm.wakeUpCheckEnabled else { return }
        await scheduleWakeCheck(
            for: alarm,
            delay: TimeInterval(alarm.wakeUpCheckDelay * 60),
            response: TimeInterval(max(1, alarm.wakeUpNoResponseTime) * 60))
    }

    /// "Not yet" — ring again in 5 minutes, confirmation available immediately.
    func postponeWakeUpCheck(for alarm: Alarm) async {
        await scheduleWakeCheck(for: alarm, delay: 0, response: 5 * 60)
    }

    func cancelWakeUpCheck(for alarmID: UUID) async {
        clearWakeCheckState(for: alarmID)
        await cancelReRing(for: alarmID)
        refreshActiveCycles()
    }

    func wakeCheckState(for alarmID: UUID) -> WakeCheckState? {
        loadWakeCheckStates().first { $0.alarmID == alarmID }
    }

    private func scheduleWakeCheck(for alarm: Alarm, delay: TimeInterval, response: TimeInterval) async {
        await cancelWakeUpCheck(for: alarm.id)
        let now = Date()
        var states = loadWakeCheckStates()
        states.append(WakeCheckState(
            alarmID: alarm.id,
            delayEnd: now.addingTimeInterval(delay),
            ringDate: now.addingTimeInterval(delay + response)))
        saveWakeCheckStates(states)
        await scheduleReRing(for: alarm, after: delay + response)
        refreshActiveCycles()
    }

    private func loadWakeCheckStates() -> [WakeCheckState] {
        guard let data = UserDefaults.standard.data(forKey: wakeCheckStatesKey),
              let states = try? JSONDecoder().decode([WakeCheckState].self, from: data) else { return [] }
        return states
    }

    private func saveWakeCheckStates(_ states: [WakeCheckState]) {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: wakeCheckStatesKey)
        }
    }

    private func clearWakeCheckState(for alarmID: UUID) {
        saveWakeCheckStates(loadWakeCheckStates().filter { $0.alarmID != alarmID })
    }

    // MARK: - Configuration builders

    // Note: our own `Alarm` model shadows AlarmKit's `Alarm` type, so AlarmKit's
    // nested types must be written fully qualified (AlarmKit.Alarm.…).
    //
    // `countdownPreAlert` (seconds) turns the config into a system countdown
    // timer: scheduled with `schedule: nil`, the OS renders a ticking countdown
    // (Lock Screen / Dynamic Island) and alerts when it reaches zero. Only the
    // snooze ring uses it — the main alarm and the swipe-proof wake-up re-ring
    // pass nil and carry no system countdown.
    private func makeConfiguration(
        for alarm: Alarm,
        schedule: AlarmKit.Alarm.Schedule?,
        firingID: UUID,
        title: String,
        countdownPreAlert: TimeInterval? = nil
    ) -> AlarmManager.AlarmConfiguration<EmptyMetadata> {
        let stopButton = AlarmButton(
            text: "Stop",
            textColor: .white,
            systemImageName: "stop.circle")

        // No-snooze alarms show only the Stop button on the system alarm screen.
        let alert: AlarmPresentation.Alert
        if alarm.snoozeEnabled {
            // Show how long the snooze lasts right on the alarm screen's button,
            // e.g. "Snooze 5 min" / "Drzemka 5 min".
            let snoozeButton = AlarmButton(
                text: "Snooze \(durationText(minutes: alarm.snoozeDuration))",
                textColor: .white,
                systemImageName: "moon.zzz.fill")
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stopButton,
                secondaryButton: snoozeButton,
                secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: stopButton)
        }

        let presentation: AlarmPresentation
        let countdownDuration: AlarmKit.Alarm.CountdownDuration?
        if let preAlert = countdownPreAlert {
            let countdown = AlarmPresentation.Countdown(
                title: LocalizedStringResource(stringLiteral: title),
                pauseButton: nil)
            presentation = AlarmPresentation(alert: alert, countdown: countdown)
            countdownDuration = AlarmKit.Alarm.CountdownDuration(preAlert: preAlert, postAlert: nil)
        } else {
            presentation = AlarmPresentation(alert: alert)
            countdownDuration = nil
        }

        let attributes = AlarmAttributes<EmptyMetadata>(
            presentation: presentation,
            tintColor: .orange)

        return AlarmManager.AlarmConfiguration(
            countdownDuration: countdownDuration,
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: alarm.id.uuidString,
                                        firingID: firingID.uuidString),
            secondaryIntent: alarm.snoozeEnabled
                ? SnoozeAlarmIntent(alarmID: alarm.id.uuidString,
                                    firingID: firingID.uuidString)
                : nil,
            sound: soundFile(for: alarm).map { .named($0) } ?? .default)
    }

    /// File name of the custom tone, or nil for the system default sound.
    /// Volume is not configurable — alarms play at the system ringer volume.
    private func soundFile(for alarm: Alarm) -> String? {
        availableSounds.first(where: { $0.id == alarm.soundName })?.fileName
    }

    private func makeSchedule(for alarm: Alarm) -> AlarmKit.Alarm.Schedule? {
        switch alarm.repeatSchedule {
        case .once:
            guard let next = alarm.nextFireDate() else { return nil }
            return .fixed(next)
        case .weekdays(let days):
            let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: alarm.hour, minute: alarm.minute)
            let recurrence = AlarmKit.Alarm.Schedule.Relative.Recurrence.weekly(
                days.map(\.localeWeekday))
            return .relative(AlarmKit.Alarm.Schedule.Relative(time: time, repeats: recurrence))
        }
    }

    // MARK: - Re-ring ID persistence
    // The re-ring is a separate AlarmKit alarm with its own UUID; remember the
    // mapping so it can be cancelled when the user confirms they're awake.

    private func storedID(for alarmID: UUID, in mapKey: String) -> UUID? {
        let map = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String]
        guard let str = map?[alarmID.uuidString] else { return nil }
        return UUID(uuidString: str)
    }

    private func saveID(_ id: UUID, for alarmID: UUID, in mapKey: String) {
        var map = (UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String]) ?? [:]
        map[alarmID.uuidString] = id.uuidString
        UserDefaults.standard.set(map, forKey: mapKey)
    }

    private func removeID(for alarmID: UUID, in mapKey: String) {
        var map = (UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String]) ?? [:]
        map.removeValue(forKey: alarmID.uuidString)
        UserDefaults.standard.set(map, forKey: mapKey)
    }
}
