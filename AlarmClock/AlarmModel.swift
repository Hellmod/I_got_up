import Foundation
import SwiftUI

// MARK: - Weekday

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    /// Localized short weekday name from the system calendar (e.g. "Mon", "pon.").
    var shortName: String {
        Calendar.current.shortStandaloneWeekdaySymbols[rawValue - 1]
    }

    var calendarWeekday: Int { rawValue }

    /// Mapping for AlarmKit's weekly recurrence.
    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: return .sunday
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        }
    }
}

// MARK: - AlarmRepeat

enum AlarmRepeat: Codable, Equatable {
    case once
    case weekdays(Set<Weekday>)

    var displayText: String {
        switch self {
        case .once:
            return String(localized: "Once")
        case .weekdays(let days):
            if days.count == 7 { return String(localized: "Every day") }
            if days == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) { return String(localized: "Weekdays") }
            if days == Set([.saturday, .sunday]) { return String(localized: "Weekends") }
            return days.sorted { $0.rawValue < $1.rawValue }.map(\.shortName).joined(separator: ", ")
        }
    }
}

// MARK: - Alarm

struct Alarm: Identifiable, Codable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    var label: String
    var isEnabled: Bool = true
    var repeatSchedule: AlarmRepeat = .once
    var soundName: String = "default"
    var snoozeDuration: Int = 5
    var wakeUpCheckEnabled: Bool = true
    var wakeUpCheckDelay: Int = 3       // minutes after dismissal before first check
    var wakeUpNoResponseTime: Int = 3   // minutes of reminders before re-ringing

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    // MARK: Countdown

    func nextFireDate() -> Date? {
        guard isEnabled else { return nil }
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        let cal = Calendar.current
        switch repeatSchedule {
        case .once:
            return cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
        case .weekdays(let days):
            return days.compactMap { day -> Date? in
                var c = comps
                c.weekday = day.calendarWeekday
                return cal.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime)
            }.min()
        }
    }

    func countdownString() -> String? {
        guard let next = nextFireDate() else { return nil }
        let diff = Int(next.timeIntervalSince(Date()))
        guard diff > 0 else { return nil }
        let totalMin = diff / 60
        let hours = totalMin / 60
        let minutes = totalMin % 60
        if hours >= 24 {
            let days = hours / 24
            let h = hours % 24
            return h > 0 ? String(localized: "In \(days) d \(h) h") : String(localized: "In \(days) d")
        }
        if hours > 0 { return String(localized: "In \(hours) h \(minutes) min") }
        if minutes > 0 { return String(localized: "In \(minutes) min") }
        return String(localized: "Soon")
    }
}

// MARK: - AlarmStore

class AlarmStore: ObservableObject {
    @Published var alarms: [Alarm] = []
    private let key = "saved_alarms"

    init() { load() }

    func add(_ alarm: Alarm) { alarms.append(alarm); save() }

    func update(_ alarm: Alarm) {
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx] = alarm; save()
        }
    }

    func delete(at offsets: IndexSet) { alarms.remove(atOffsets: offsets); save() }
    func delete(_ alarm: Alarm) { alarms.removeAll { $0.id == alarm.id }; save() }

    func toggle(_ alarm: Alarm) {
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx].isEnabled.toggle(); save()
        }
    }

    func reload() { load() }

    private func save() {
        if let data = try? JSONEncoder().encode(alarms) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Alarm].self, from: data) else { return }
        alarms = decoded
    }
}

// MARK: - Alarm History

enum HistoryAction: String, Codable {
    case dismissed, snoozed, wakeConfirmed, wakePostponed, autoReRing

    var label: String {
        switch self {
        case .dismissed:    return String(localized: "Dismissed")
        case .snoozed:      return String(localized: "Snoozed")
        case .wakeConfirmed: return String(localized: "I'm up ✅")
        case .wakePostponed: return String(localized: "Not yet 😴")
        case .autoReRing:   return String(localized: "Re-ring")
        }
    }

    var systemImage: String {
        switch self {
        case .dismissed:    return "xmark.circle"
        case .snoozed:      return "moon.zzz"
        case .wakeConfirmed: return "checkmark.circle"
        case .wakePostponed: return "zzz"
        case .autoReRing:   return "alarm.waves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .dismissed:    return .red
        case .snoozed:      return .orange
        case .wakeConfirmed: return .green
        case .wakePostponed: return .yellow
        case .autoReRing:   return .purple
        }
    }
}

struct AlarmHistoryEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var alarmID: UUID
    var alarmLabel: String
    var scheduledHour: Int
    var scheduledMinute: Int
    var firedAt: Date
    var action: HistoryAction
    var detail: String?

    var scheduledTimeString: String {
        String(format: "%02d:%02d", scheduledHour, scheduledMinute)
    }
}

class AlarmHistoryStore: ObservableObject {
    @Published var entries: [AlarmHistoryEntry] = []
    private let key = "alarm_history_v1"
    private let maxEntries = 200

    init() { load() }

    func record(alarm: Alarm, action: HistoryAction, detail: String? = nil) {
        let entry = AlarmHistoryEntry(
            alarmID: alarm.id,
            alarmLabel: alarm.label,
            scheduledHour: alarm.hour,
            scheduledMinute: alarm.minute,
            firedAt: Date(),
            action: action,
            detail: detail
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save()
    }

    func entries(for alarmID: UUID) -> [AlarmHistoryEntry] {
        entries.filter { $0.alarmID == alarmID }
    }

    func clear() { entries.removeAll(); save() }

    func reload() { load() }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AlarmHistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
