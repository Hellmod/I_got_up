import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

// MARK: - AlarmWidgetsBundle
//
// Live Activity for AlarmKit countdowns. Required: without a widget extension
// rendering AlarmAttributes, the system has no countdown UI to show and may
// refuse to schedule alarms that carry a CountdownDuration.

@main
struct AlarmWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AlarmCountdownLiveActivity()
    }
}

// MARK: - AlarmCountdownLiveActivity

struct AlarmCountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<EmptyMetadata>.self) { context in
            // Lock Screen / banner presentation
            HStack(spacing: 14) {
                Image(systemName: "alarm.fill")
                    .font(.title2)
                    .foregroundStyle(context.attributes.tintColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: context))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    countdownText(for: context)
                        .font(.title)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "alarm.fill")
                        .font(.title2)
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(for: context)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(context.attributes.tintColor)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(title(for: context))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            } compactTrailing: {
                countdownText(for: context)
                    .monospacedDigit()
                    .foregroundStyle(context.attributes.tintColor)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(context.attributes.tintColor)
            }
        }
    }

    // MARK: - Helpers

    private func title(for context: ActivityViewContext<AlarmAttributes<EmptyMetadata>>) -> String {
        switch context.state.mode {
        case .countdown:
            if let title = context.attributes.presentation.countdown?.title {
                return String(localized: title)
            }
        case .paused:
            if let title = context.attributes.presentation.paused?.title {
                return String(localized: title)
            }
        default:
            break
        }
        return String(localized: context.attributes.presentation.alert.title)
    }

    @ViewBuilder
    private func countdownText(for context: ActivityViewContext<AlarmAttributes<EmptyMetadata>>) -> some View {
        switch context.state.mode {
        case .countdown(let countdown):
            Text(timerInterval: Date.now...countdown.fireDate, countsDown: true)
        default:
            Image(systemName: "bell.and.waves.left.and.right.fill")
        }
    }
}
