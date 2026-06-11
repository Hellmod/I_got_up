import SwiftUI

// MARK: - AlarmHistoryView

struct AlarmHistoryView: View {
    @EnvironmentObject private var historyStore: AlarmHistoryStore
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Record history", isOn: $historyStore.isEnabled)
                } footer: {
                    Text("When disabled, new alarm events won't be saved to history.")
                }

                if historyStore.entries.isEmpty {
                    Section {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(historyStore.entries) { entry in
                            HistoryEntryRow(entry: entry)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Alarm History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !historyStore.entries.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) {
                            showClearConfirm = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear history?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) {
                    historyStore.clear()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No History")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Alarm activity will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
    }
}

// MARK: - HistoryEntryRow

struct HistoryEntryRow: View {
    let entry: AlarmHistoryEntry

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.action.systemImage)
                .font(.title3)
                .foregroundStyle(entry.action.color)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.scheduledTimeString)
                        .font(.system(.headline, design: .rounded))
                    if !entry.alarmLabel.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(entry.alarmLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    Text(entry.action.label)
                        .font(.subheadline)
                        .foregroundStyle(entry.action.color)
                    if let detail = entry.detail {
                        Text("(\(detail))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(entry.firedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let store = AlarmHistoryStore()
    let alarm = Alarm(id: UUID(), hour: 7, minute: 30, label: "Praca")
    store.record(alarm: alarm, action: .dismissed)
    store.record(alarm: alarm, action: .snoozed, detail: "5 min")
    store.record(alarm: alarm, action: .wakeConfirmed)
    return AlarmHistoryView()
        .environmentObject(store)
}
