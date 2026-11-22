#if DEBUG
import Foundation

/// The DEBUG launches the check scripts drive: the snapshot renderer
/// (`silent_launch_check.sh`), the uninstall self-test (`uninstall_check.sh`) and the
/// quit-with-the-sheet-open test (`quit_check.sh`). Each is a real launch of the real
/// app, so each must leave no trace — no network, nothing written to the owner's
/// preferences.
///
/// 2026-11-22 (#17): one list instead of the same environment check copied into every
/// place that has to stand down. With a third launch kind, a copy that missed it would
/// have written the owner's settings or gone to the network during a check.
enum CheckLaunch {
    static let environmentKeys = ["POMO_SNAPSHOT", "POMO_UNINSTALL_SELFTEST", "POMO_QUIT_SELFTEST"]

    static var isActive: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environmentKeys.contains { environment[$0] != nil }
    }
}
#endif
