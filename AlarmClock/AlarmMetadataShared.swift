import AlarmKit

/// Empty metadata for AlarmAttributes. Shared between the app target and the
/// widget extension so both processes reference the same Live Activity
/// attributes type (AlarmAttributes<EmptyMetadata>).
struct EmptyMetadata: AlarmMetadata {}
