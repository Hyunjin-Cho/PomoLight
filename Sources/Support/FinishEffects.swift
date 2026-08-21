import Foundation

// The four things a finished timer does — ring, notify, raise the window, release
// the sleep assertion — are wired together in `AppModel.handleFinish()`, and until
// 2026-08-21 nothing checked that wiring. Deleting any one of those lines left a
// green build and a green test suite; the only detector was a human noticing that
// the alarm had gone quiet. Given that this app's real accidents have all been of
// exactly that shape (a launch-time tick, an invisible heart, settings wiped by a
// snapshot run), the wiring is worth a test.
//
// It could not have one before, because `AppModel` built its collaborators itself.
// A test that let those run would open the audio device and ask the real
// notification centre for permission. These protocols are the seam: the app passes
// the real parts, a test passes recorders that only remember what they were told.
// The names describe the JOB, not the class, so the test reads as a description of
// behaviour rather than of plumbing.

/// Makes the alarm audible. `ChimePlayer` in the app.
@MainActor
protocol AlarmPlaying: AnyObject {
    func playAlarm(sound: AlarmSound, volume: Double, repeatUntilDismissed: Bool)
    func preview(sound: AlarmSound, volume: Double)
    func stop()
}

/// Delivers the backup banner and owns the permission it needs.
/// `NotificationManager` in the app.
@MainActor
protocol FinishNotifying: AnyObject {
    func configureDelegate()
    func requestAuthorizationIfNeeded()
    func notifyTimerFinished(enabled: Bool)
}

/// Holds the Mac awake while a timer runs. `PowerAssertion` in the app.
@MainActor
protocol SleepPreventing: AnyObject {
    func setActive(_ active: Bool)
}

/// Surfaces the window when the timer ends.
///
/// This one exists only because `AppActivation` is an enum of static functions
/// rather than an object, so there is nothing to substitute. Rather than reshape
/// it (`AppDelegate` and `RootView` both call it directly and are fine as they
/// are), give `AppModel` an object-shaped handle onto it.
@MainActor
protocol WindowRaising: AnyObject {
    func bringToFront()
}

extension ChimePlayer: AlarmPlaying {}
extension NotificationManager: FinishNotifying {}
extension PowerAssertion: SleepPreventing {}

@MainActor
final class SystemWindowRaiser: WindowRaising {
    func bringToFront() { AppActivation.bringToFront() }
}
