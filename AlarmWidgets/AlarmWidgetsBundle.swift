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
        WakeCheckCountdownLiveActivity()
    }
}

// MARK: - WakeCheckCountdownLiveActivity
//
// Cosmetic countdown for the wake-up check cycle. The real re-ring is an
// invisible fixed-date AlarmKit alarm — dismissing this activity cancels
// nothing and the alarm still fires exactly on time.

struct WakeCheckCountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WakeCheckActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "hourglass")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(timerInterval: Date.now...max(context.state.ringDate, Date.now),
                         countsDown: true)
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
                    Image(systemName: "hourglass")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...max(context.state.ringDate, Date.now),
                         countsDown: true)
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(context.state.ringDate, Date.now),
                     countsDown: true)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            }
        }
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
