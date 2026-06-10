import Foundation

/// Optionally keeps the system (and display) awake while a timer runs, for users
/// who don't want focus sessions interrupted by sleep. Off by default.
@MainActor
final class PowerAssertion {
    private var activity: NSObjectProtocol?

    func setActive(_ active: Bool) {
        if active {
            guard activity == nil else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
                reason: "PomoLight timer running"
            )
        } else {
            if let activity {
                ProcessInfo.processInfo.endActivity(activity)
            }
            activity = nil
        }
    }
}
