import SwiftUI
import AudioToolbox

// MARK: - AddAlarmView

struct AddAlarmView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AlarmStore

    var editingAlarm: Alarm?

    @State private var selectedTime: Date
    @State private var label: String
    @State private var repeatSchedule: AlarmRepeat
    @State private var selectedSound: String
    @State private var snoozeDuration: Int
    @State private var wakeUpCheckEnabled: Bool
    @State private var wakeUpCheckDelay: Int

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
        _snoozeDuration = State(initialValue: alarm?.snoozeDuration ?? 5)
        _wakeUpCheckEnabled = State(initialValue: alarm?.wakeUpCheckEnabled ?? true)
        _wakeUpCheckDelay = State(initialValue: alarm?.wakeUpCheckDelay ?? 3)

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
                        "Godzina alarmu",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                // Label
                Section("Etykieta") {
                    TextField("Opcjonalna nazwa alarmu", text: $label)
                }

                // Repeat
                Section("Powtarzanie") {
                    repeatRow(title: "Jednorazowo", isSelected: isOnce) {
                        repeatSchedule = .once
                        selectedWeekdays = []
                    }
                    ForEach(Weekday.allCases) { day in
                        weekdayRow(day)
                    }
                }

                // Sound
                Section("Dźwięk") {
                    Button {
                        showSoundPicker = true
                    } label: {
                        HStack {
                            Text("Dźwięk alarmu")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(availableSounds.first(where: { $0.id == selectedSound })?.displayName ?? "Domyślny")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Drzemka", selection: $snoozeDuration) {
                        Text("5 minut").tag(5)
                        Text("10 minut").tag(10)
                        Text("15 minut").tag(15)
                    }
                }

                // Wake-Up Check
                Section {
                    Toggle("Wake-Up Check", isOn: $wakeUpCheckEnabled)

                    if wakeUpCheckEnabled {
                        Stepper(
                            "Opóźnienie: \(wakeUpCheckDelay) min",
                            value: $wakeUpCheckDelay,
                            in: 1...10
                        )
                    }
                } header: {
                    Text("Weryfikacja obudzenia")
                } footer: {
                    if wakeUpCheckEnabled {
                        Text("Po wyłączeniu alarmu, po \(wakeUpCheckDelay) min. zostanie wysłane powiadomienie z prośbą o potwierdzenie. Brak odpowiedzi przez 3 minuty = ponowny dzwonek.")
                    }
                }
            }
            .navigationTitle(editingAlarm == nil ? "Nowy alarm" : "Edytuj alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { save() }
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
            snoozeDuration: snoozeDuration,
            wakeUpCheckEnabled: wakeUpCheckEnabled,
            wakeUpCheckDelay: wakeUpCheckDelay
        )

        if editingAlarm != nil {
            AlarmScheduler.shared.alarmUpdated(alarm, store: store)
        } else {
            AlarmScheduler.shared.alarmAdded(alarm, store: store)
        }
        dismiss()
    }
}

// MARK: - SoundPickerView

struct SoundPickerView: View {
    @Binding var selectedSound: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(availableSounds) { sound in
                Button {
                    selectedSound = sound.id
                    previewSound()
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
            .navigationTitle("Wybierz dźwięk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Gotowe") { dismiss() }
                }
            }
        }
    }

    private func previewSound() {
        // Sound ID 1005 = system alarm sound. Plays a short preview on tap.
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }
}

#Preview {
    AddAlarmView()
        .environmentObject(AlarmStore())
}
