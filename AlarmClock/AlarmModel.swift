import Foundation
import SwiftUI

// MARK: - Weekday

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .sunday: return "Nd"
        case .monday: return "Pn"
        case .tuesday: return "Wt"
        case .wednesday: return "Śr"
        case .thursday: return "Cz"
        case .friday: return "Pt"
        case .saturday: return "So"
        }
    }

    var calendarWeekday: Int { rawValue }
}

// MARK: - AlarmRepeat

enum AlarmRepeat: Codable, Equatable {
    case once
    case weekdays(Set<Weekday>)

    var displayText: String {
        switch self {
        case .once:
            return "Jednorazowo"
        case .weekdays(let days):
            if days.count == 7 { return "Codziennie" }
            if days == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) { return "Dni robocze" }
            if days == Set([.saturday, .sunday]) { return "Weekendy" }
            let sorted = days.sorted { $0.rawValue < $1.rawValue }
            return sorted.map(\.shortName).joined(separator: ", ")
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
    var snoozeDuration: Int = 5 // minutes
    var wakeUpCheckEnabled: Bool = true
    var wakeUpCheckDelay: Int = 3 // minutes after dismissal before sending check

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

// MARK: - AlarmStore

class AlarmStore: ObservableObject {
    @Published var alarms: [Alarm] = []

    private let key = "saved_alarms"

    init() {
        load()
    }

    func add(_ alarm: Alarm) {
        alarms.append(alarm)
        save()
    }

    func update(_ alarm: Alarm) {
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx] = alarm
            save()
        }
    }

    func delete(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
        save()
    }

    func delete(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        save()
    }

    func toggle(_ alarm: Alarm) {
        if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[idx].isEnabled.toggle()
            save()
        }
    }

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

// MARK: - Available Sounds

struct AlarmSound: Identifiable, Hashable {
    let id: String
    let displayName: String
    var fileName: String? // nil = system default tone via notification
}

let availableSounds: [AlarmSound] = [
    AlarmSound(id: "default", displayName: "Domyślny", fileName: nil),
    AlarmSound(id: "alarm", displayName: "Alarm", fileName: "alarm.caf"),
    AlarmSound(id: "anticipate", displayName: "Anticipate", fileName: "Anticipate.caf"),
    AlarmSound(id: "bloom", displayName: "Bloom", fileName: "Bloom.caf"),
    AlarmSound(id: "calypso", displayName: "Calypso", fileName: "Calypso.caf"),
    AlarmSound(id: "chime", displayName: "Dzwonki", fileName: "Chime.caf"),
    AlarmSound(id: "chord", displayName: "Akord", fileName: "Chord.caf"),
    AlarmSound(id: "descent", displayName: "Descent", fileName: "Descent.caf"),
    AlarmSound(id: "fanfare", displayName: "Fanfara", fileName: "Fanfare.caf"),
    AlarmSound(id: "ladder", displayName: "Ladder", fileName: "Ladder.caf"),
    AlarmSound(id: "minuet", displayName: "Minuet", fileName: "Minuet.caf"),
    AlarmSound(id: "news_flash", displayName: "News Flash", fileName: "News Flash.caf"),
    AlarmSound(id: "noir", displayName: "Noir", fileName: "Noir.caf"),
    AlarmSound(id: "sherwood_forest", displayName: "Sherwood", fileName: "Sherwood Forest.caf"),
    AlarmSound(id: "spell", displayName: "Spell", fileName: "Spell.caf"),
    AlarmSound(id: "suspense", displayName: "Suspense", fileName: "Suspense.caf"),
    AlarmSound(id: "telegraph", displayName: "Telegraf", fileName: "Telegraph.caf"),
    AlarmSound(id: "tiptoes", displayName: "Tiptoes", fileName: "Tiptoes.caf"),
    AlarmSound(id: "typewriters", displayName: "Maszyna", fileName: "Typewriters.caf"),
    AlarmSound(id: "update", displayName: "Update", fileName: "Update.caf"),
]
