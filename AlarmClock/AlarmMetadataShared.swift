import ActivityKit
import AlarmKit
import Foundation

/// Empty metadata for AlarmAttributes. Shared between the app target and the
/// widget extension so both processes reference the same Live Activity
/// attributes type (AlarmAttributes<EmptyMetadata>).
struct EmptyMetadata: AlarmMetadata {}

/// Attributes of the cosmetic wake-up-check countdown Live Activity.
/// The real re-ring is a separate invisible fixed-date AlarmKit alarm, so
/// swiping this activity away dismisses only the UI — never the alarm.
struct WakeCheckActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var ringDate: Date
    }

    var alarmID: String
    var title: String   // localized in the app process before starting
}
