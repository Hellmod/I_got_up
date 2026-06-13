import AVFoundation
import SwiftUI

// MARK: - AddAlarmView

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AlarmStore

    var editingAlarm: Alarm?

    @State private var selectedTime: Date
    @State private var label: String
    @State private var repeatSchedule: AlarmRepeat
    @State private var selectedSound: String
    @State private var snoozeEnabled: Bool
    @State private var snoozeDuration: Int
    @State private var wakeUpCheckEnabled: Bool
    @State private var wakeUpCheckDelay: Int
    @State private var wakeUpNoResponseTime: Int

    @State private var showSoundPicker = false
    @State private var selectedWeekdays: Set<Weekday>

    init(editingAlarm: Alarm? = nil) {
        self.editingAlarm = editingAlarm

        let alarm = editingAlarm
        var components = DateComponents()
        components.hour = alarm?.hour ?? 7
        components.minute = alarm?.minute ?? 0
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? Date()

        _selectedTime = State(initialValue: date)
        _label = State(initialValue: alarm?.label ?? "")
        _selectedSound = State(initialValue: alarm?.soundName ?? "default")
        _snoozeEnabled = State(initialValue: alarm?.snoozeEnabled ?? true)
        _snoozeDuration = State(initialValue: alarm?.snoozeDuration ?? 5)
        _wakeUpCheckEnabled = State(initialValue: alarm?.wakeUpCheckEnabled ?? true)
        _wakeUpCheckDelay = State(initialValue: alarm?.wakeUpCheckDelay ?? 3)
        _wakeUpNoResponseTime = State(initialValue: alarm?.wakeUpNoResponseTime ?? 3)

        if case .weekdays(let days) = alarm?.repeatSchedule {
            _selectedWeekdays = State(initialValue: days)
            _repeatSchedule = State(initialValue: .weekdays(days))
        } else {
            _selectedWeekdays = State(initialValue: [])
            _repeatSchedule = State(initialValue: alarm?.repeatSchedule ?? .once)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Time picker
                Section {
                    DatePicker(
                        "Alarm time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                // Label
                Section("Label") {
                    TextField("Optional alarm name", text: $label)
                }

                // Repeat
                Section("Repeat") {
                    repeatRow(title: String(localized: "Once"), isSelected: isOnce) {
                        repeatSchedule = .once
                        selectedWeekdays = []
                    }
                    ForEach(Weekday.allCases) { day in
                        weekdayRow(day)
                    }
                }

                // Sound — volume itself always follows the system ringer
                Section {
                    Button {
                        showSoundPicker = true
                    } label: {
                        HStack {
                            Text("Alarm sound")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(availableSounds.first(where: { $0.id == selectedSound })?.displayName ?? "")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Sound")
                } footer: {
                    Text("Volume follows the system ringtone volume.")
                }

                // Snooze — when disabled the system alarm shows only a Stop button
                Section("Snooze") {
                    Toggle("Snooze", isOn: $snoozeEnabled)
                    if snoozeEnabled {
                        DurationPickerRow(title: "Snooze duration", minutes: $snoozeDuration)
                    }
                }

                // Wake-Up Check
                Section {
                    Toggle("Wake-Up Check", isOn: $wakeUpCheckEnabled)

                    if wakeUpCheckEnabled {
                        DurationPickerRow(title: "Delay", minutes: $wakeUpCheckDelay,
                                          allowZero: true)
                        DurationPickerRow(title: "Re-ring after no response",
                                          minutes: $wakeUpNoResponseTime)
                    }
                } header: {
                    Text("Wake-up verification")
                } footer: {
                    if wakeUpCheckEnabled {
                        Text("After stopping the alarm, a \(durationText(minutes: wakeUpCheckDelay)) delay starts during which you can't confirm yet. Then you have \(durationText(minutes: wakeUpNoResponseTime)) to confirm you're up — otherwise the alarm rings again.")
                    }
                }
            }
            .navigationTitle(editingAlarm == nil ? Text("New Alarm") : Text("Edit Alarm"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showSoundPicker) {
                SoundPickerView(selectedSound: $selectedSound)
            }
        }
    }

    // MARK: - Helpers

    private var isOnce: Bool {
        if case .once = repeatSchedule { return true }
        return false
    }

    private func repeatRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func weekdayRow(_ day: Weekday) -> some View {
        Button {
            toggleWeekday(day)
        } label: {
            HStack {
                Text(day.shortName)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedWeekdays.contains(day) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func toggleWeekday(_ day: Weekday) {
        if selectedWeekdays.contains(day) {
            selectedWeekdays.remove(day)
        } else {
            selectedWeekdays.insert(day)
        }
        if selectedWeekdays.isEmpty {
            repeatSchedule = .once
        } else {
            repeatSchedule = .weekdays(selectedWeekdays)
        }
    }

    private func save() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: selectedTime)
        let hour = components.hour ?? 7
        let minute = components.minute ?? 0

        let schedule = selectedWeekdays.isEmpty ? AlarmRepeat.once : AlarmRepeat.weekdays(selectedWeekdays)

        let alarm = Alarm(
            id: editingAlarm?.id ?? UUID(),
            hour: hour,
            minute: minute,
            label: label.trimmingCharacters(in: .whitespaces),
            isEnabled: editingAlarm?.isEnabled ?? true,
            repeatSchedule: schedule,
            soundName: selectedSound,
            snoozeEnabled: snoozeEnabled,
            snoozeDuration: snoozeDuration,
            wakeUpCheckEnabled: wakeUpCheckEnabled,
            wakeUpCheckDelay: wakeUpCheckDelay,
            wakeUpNoResponseTime: wakeUpNoResponseTime
        )

        if editingAlarm != nil {
            AlarmScheduler.shared.alarmUpdated(alarm, store: store)
        } else {
            AlarmScheduler.shared.alarmAdded(alarm, store: store)
        }
        dismiss()
    }
}

// MARK: - DurationPickerRow

/// Form row with the formatted duration; tapping it expands hour/minute
/// wheels so any value can be dialed in (0–12 h, 0–59 min).
struct DurationPickerRow: View {
    let title: LocalizedStringKey
    @Binding var minutes: Int
    var allowZero: Bool = false

    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation { expanded.toggle() }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(durationText(minutes: minutes))
                    .foregroundStyle(expanded ? Color.orange : Color.secondary)
            }
        }

        if expanded {
            HStack(spacing: 4) {
                Picker("", selection: hoursBinding) {
                    ForEach(0...12, id: \.self) { h in
                        Text("\(h)").tag(h)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
                Text("h")
                    .foregroundStyle(.secondary)

                Picker("", selection: minutesBinding) {
                    ForEach(0...59, id: \.self) { m in
                        Text("\(m)").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
                Text("min")
                    .foregroundStyle(.secondary)
            }
            .frame(height: 130)
        }
    }

    private var hoursBinding: Binding<Int> {
        Binding(
            get: { minutes / 60 },
            set: { minutes = clamped($0 * 60 + minutes % 60) }
        )
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { minutes % 60 },
            set: { minutes = clamped((minutes / 60) * 60 + $0) }
        )
    }

    private func clamped(_ value: Int) -> Int {
        (!allowZero && value == 0) ? 1 : value
    }
}

// MARK: - SoundPickerView

struct SoundPickerView: View {
    @Binding var selectedSound: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVAudioPlayer?

    var body: some View {
        NavigationStack {
            List(availableSounds) { sound in
                Button {
                    selectedSound = sound.id
                    preview(sound)
                } label: {
                    HStack {
                        Text(sound.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedSound == sound.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                        Image(systemName: "play.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Choose sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear { player?.stop() }
        }
    }

    private func preview(_ sound: AlarmSound) {
        player?.stop()
        guard let fileName = sound.fileName,
              let url = AlarmToneGenerator.fileURL(for: fileName) else {
            player = nil
            return // system default has no local file to preview
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}

#Preview {
    AddAlarmView()
        .environmentObject(AlarmStore())
}
