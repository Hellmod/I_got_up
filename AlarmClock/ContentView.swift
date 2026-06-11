import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var historyStore: AlarmHistoryStore
    @EnvironmentObject private var alarmKit: AlarmKitManager

    @State private var showAddAlarm = false
    @State private var alarmToEdit: Alarm?
    @State private var showHistory = false
    @State private var showOnboarding = false
    @AppStorage("onboarding_seen_v1") private var onboardingSeen = false

    var body: some View {
        NavigationStack {
            Group {
                if store.alarms.isEmpty {
                    emptyState
                } else {
                    alarmList
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddAlarm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showHistory = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("How it works", systemImage: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddAlarm) {
                AddAlarmView()
            }
            .sheet(item: $alarmToEdit) { alarm in
                AddAlarmView(editingAlarm: alarm)
            }
            .sheet(isPresented: $showHistory) {
                AlarmHistoryView()
                    .environmentObject(historyStore)
            }
            .sheet(isPresented: $showOnboarding, onDismiss: { onboardingSeen = true }) {
                OnboardingView()
            }
            .onAppear {
                if !onboardingSeen { showOnboarding = true }
            }
            .overlay(permissionBanner, alignment: .top)
        }
        // Wake-up confirmation screen (two-phase countdown).
        .fullScreenCover(item: Binding(
            get: { alarmKit.pendingWakeUpAlarm },
            set: { alarmKit.pendingWakeUpAlarm = $0 }
        )) { alarm in
            WakeUpCheckView(alarm: alarm)
                .environmentObject(alarmKit)
                .environmentObject(historyStore)
        }
        // Reload state when app returns to foreground — alarms stopped, snoozed or
        // disabled by intents while we were in background must show up in the UI.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            store.reload()
            historyStore.reload()
            // Wake-up check countdown is running (user tapped the Live Activity
            // or just opened the app) — show the confirmation screen directly.
            if alarmKit.pendingWakeUpAlarm == nil,
               let id = AlarmKitManager.shared.alarmIDsWithPendingReRing().first,
               let alarm = store.alarms.first(where: { $0.id == id }) {
                alarmKit.pendingWakeUpAlarm = alarm
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "alarm")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No Alarms")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Tap + to add a new alarm")
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
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var permissionBanner: some View {
        VStack(spacing: 8) {
            if alarmKit.permissionDenied {
                banner(icon: "alarm.waves.left.and.right",
                       title: "Alarms permission missing",
                       message: "The alarm won't ring — enable alarms in Settings.")
            }
        }
    }

    private func banner(icon: String, title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button("Enable") { openSettings() }
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

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
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

                if alarm.isEnabled {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        if let countdown = alarm.countdownString() {
                            Text(countdown)
                                .font(.caption)
                                .foregroundStyle(.orange.opacity(0.9))
                        }
                    }
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
        .environmentObject(AlarmHistoryStore())
        .environmentObject(AlarmKitManager.shared)
}
