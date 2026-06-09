import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var notificationManager: NotificationManager

    @State private var showAddAlarm = false
    @State private var alarmToEdit: Alarm?
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if store.alarms.isEmpty {
                    emptyState
                } else {
                    alarmList
                }
            }
            .navigationTitle("Budzik")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if notificationManager.permissionDenied {
                            showPermissionAlert = true
                        } else {
                            showAddAlarm = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        openNotificationSettings()
                    } label: {
                        Label("Ustawienia powiadomień", systemImage: "bell.badge")
                    }
                }
            }
            .sheet(isPresented: $showAddAlarm) {
                AddAlarmView()
            }
            .sheet(item: $alarmToEdit) { alarm in
                AddAlarmView(editingAlarm: alarm)
            }
            .alert("Brak uprawnień", isPresented: $showPermissionAlert) {
                Button("Ustawienia") { openSettings() }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Aby alarmy działały, włącz powiadomienia dla tej aplikacji w Ustawieniach.")
            }
            .overlay(permissionBanner, alignment: .top)
        }
        // Full-screen alarm UI shown when alarm fires while app is in foreground.
        .fullScreenCover(item: Binding(
            get: { notificationManager.firingAlarm },
            set: { notificationManager.firingAlarm = $0 }
        )) { alarm in
            AlarmActiveView(alarm: alarm)
                .environmentObject(notificationManager)
                .environmentObject(store)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "alarm")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Brak alarmów")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Dotknij + aby dodać nowy alarm")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var alarmList: some View {
        List {
            ForEach(store.alarms.sorted { lhs, rhs in
                if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
                return lhs.minute < rhs.minute
            }) { alarm in
                AlarmRow(alarm: alarm)
                    .contentShape(Rectangle())
                    .onTapGesture { alarmToEdit = alarm }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            AlarmScheduler.shared.alarmDeleted(alarm, store: store)
                        } label: {
                            Label("Usuń", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if notificationManager.permissionDenied {
            HStack {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Powiadomienia wyłączone")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text("Alarmy nie będą działać bez uprawnień.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Button("Włącz") { openSettings() }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.25))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.red)
            .cornerRadius(12)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - AlarmRow

struct AlarmRow: View {
    let alarm: Alarm
    @EnvironmentObject private var store: AlarmStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.timeString)
                    .font(.system(size: 44, weight: .thin, design: .rounded))
                    .foregroundStyle(alarm.isEnabled ? .primary : .secondary)

                HStack(spacing: 6) {
                    if !alarm.label.isEmpty {
                        Text(alarm.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(alarm.repeatSchedule.displayText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if alarm.wakeUpCheckEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.caption)
                        Text("Wake-Up Check \(alarm.wakeUpCheckDelay) min")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue.opacity(0.8))
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in
                    var mutable = alarm
                    AlarmScheduler.shared.toggle(&mutable, in: store)
                }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let store = AlarmStore()
    store.add(Alarm(id: UUID(), hour: 7, minute: 30, label: "Praca", repeatSchedule: .weekdays([.monday, .tuesday, .wednesday, .thursday, .friday])))
    store.add(Alarm(id: UUID(), hour: 9, minute: 0, label: "Weekend", repeatSchedule: .weekdays([.saturday, .sunday]), wakeUpCheckEnabled: false))
    return ContentView()
        .environmentObject(store)
        .environmentObject(NotificationManager.shared)
}
