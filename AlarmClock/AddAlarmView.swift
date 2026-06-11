import SwiftUI

// MARK: - AddAlarmView

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AlarmStore

    var editingAlarm: Alarm?

    @State private var selectedTime: Date
    @State private var label: String
    @State private var repeatSchedule: AlarmRepeat
    @State private var snoozeDuration: Int
    @State private var wakeUpCheckEnabled: Bool
    @State private var wakeUpCheckDelay: Int
    @State private var wakeUpNoResponseTime: Int

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

                // Snooze — used by the system alarm's snooze button
                Section("Snooze") {
                    Picker("Snooze duration", selection: $snoozeDuration) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                    }
                }

                // Wake-Up Check
                Section {
                    Toggle("Wake-Up Check", isOn: $wakeUpCheckEnabled)

                    if wakeUpCheckEnabled {
                        Stepper(
                            "Delay: \(wakeUpCheckDelay) min",
                            value: $wakeUpCheckDelay,
                            in: 1...10
                        )
                        Stepper(
                            "Re-ring after no response: \(wakeUpNoResponseTime) min",
                            value: $wakeUpNoResponseTime,
                            in: 1...15
                        )
                    }
                } header: {
                    Text("Wake-up verification")
                } footer: {
                    if wakeUpCheckEnabled {
                        Text("After dismissing the alarm, a confirmation request arrives after \(wakeUpCheckDelay) min. No response for \(wakeUpNoResponseTime) min — the alarm rings again.")
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

#Preview {
    AddAlarmView()
        .environmentObject(AlarmStore())
}
