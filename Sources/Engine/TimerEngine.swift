import Foundation
import Observation
import AppKit

/// The single source of truth for the countdown.
///
/// It is **deadline-based**: instead of decrementing a stored number (which drifts
/// and freezes during App Nap / sleep), it remembers the absolute `Date` the timer
/// should end and always derives the remaining time from the wall clock. That makes
/// it correct across sleep/wake with trivial math.
@MainActor
@Observable
final class TimerEngine {
    enum Phase: Equatable { case idle, running, paused, finished }

    private(set) var phase: Phase = .idle
    /// The full duration the user picked, in seconds. Drives the ring proportion.
    private(set) var configuredDuration: TimeInterval

    // Internal time bookkeeping (not observed by views directly).
    @ObservationIgnored private var deadline: Date?
    @ObservationIgnored private var frozenRemaining: TimeInterval?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    /// Called exactly once when the countdown reaches zero. The app wires this to
    /// the chime, the notification, and bringing the window to the front.
    @ObservationIgnored var onFinish: (() -> Void)?

    /// A monotonically-changing value the menu-bar label observes for a ~1 Hz tick.
    private(set) var menuBarTick: Int = 0

    /// The picker's ceiling (999:00) and floor (1 s). Both `init` and `setDuration`
    /// clamp to these — 2026-08-21: `init` used to apply the floor only, so a value
    /// edited straight into `~/Library/Preferences` (`pl.lastDurationMinutes` is a
    /// plain number) reached the engine unbounded, while the same value typed into
    /// the UI was capped.
    static let minDuration: TimeInterval = 1
    static let maxDuration: TimeInterval = 999 * 60

    private static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        min(max(minDuration, seconds), maxDuration)
    }

    init(durationSeconds: TimeInterval) {
        self.configuredDuration = TimerEngine.clamp(durationSeconds)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkExpiry() }
        }
        // Belt-and-suspenders: also re-check on app activation (covers display-only
        // sleep or a stalled ticker) so a deadline passed in the background fires promptly.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkExpiry() }
        }
    }

    deinit {
        ticker?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    // MARK: - Derived time

    func remaining(at date: Date = Date()) -> TimeInterval {
        switch phase {
        case .running:  return max(0, deadline.map { $0.timeIntervalSince(date) } ?? 0)
        case .paused:   return frozenRemaining ?? configuredDuration
        case .idle:     return configuredDuration
        case .finished: return 0
        }
    }

    var remaining: TimeInterval { remaining() }

    /// Fraction of time still left (1 = full, 0 = empty). The ring trims to this.
    func fractionRemaining(at date: Date = Date()) -> Double {
        guard configuredDuration > 0 else { return 0 }
        return min(1, max(0, remaining(at: date) / configuredDuration))
    }

    var isActive: Bool { phase == .running || phase == .paused }

    // 2026-08-21: `runningDeadline` lived here so the WIDGET could run a self-ticking
    // countdown from the absolute end time. The widget went in PR #33; a grep found
    // zero production callers and six test assertions, i.e. only its own tests kept
    // it alive. Those assertions were restatements of the `remaining`/`phase` checks
    // sitting next to them, so they went with it.

    // MARK: - Configuration

    /// Set the duration. Only meaningful when not actively counting, and 2026-08-21
    /// that contract is enforced rather than merely documented: a call while running
    /// or paused used to move `configuredDuration` while leaving `deadline` alone,
    /// so `fractionRemaining` (the ring) silently described a timer that wasn't
    /// running. No UI path reaches it — the picker only shows in idle — but a
    /// half-applied change is a worse failure than a no-op.
    func setDuration(seconds: TimeInterval) {
        guard !isActive else { return }
        configuredDuration = TimerEngine.clamp(seconds)
        if phase == .finished { phase = .idle }
        if phase == .idle { frozenRemaining = nil; deadline = nil }
    }

    func setMinutes(_ minutes: Double) { setDuration(seconds: minutes * 60) }

    // MARK: - Intents

    func start() {
        guard configuredDuration > 0 else { return }
        deadline = Date().addingTimeInterval(configuredDuration)
        frozenRemaining = nil
        phase = .running
        startTicker()
    }

    func pause() {
        guard phase == .running else { return }
        frozenRemaining = remaining()
        deadline = nil
        phase = .paused
        stopTicker()
    }

    func resume() {
        guard phase == .paused else { return }
        deadline = Date().addingTimeInterval(frozenRemaining ?? configuredDuration)
        frozenRemaining = nil
        phase = .running
        startTicker()
    }

    /// The primary button action — meaning depends on the current state.
    func primaryAction() {
        switch phase {
        case .idle:     start()
        case .running:  pause()
        case .paused:   resume()
        case .finished: dismiss()
        }
    }

    /// Back to idle at the last chosen duration.
    func reset() {
        stopTicker()
        deadline = nil
        frozenRemaining = nil
        phase = .idle
    }

    /// Dismiss the finished state and return to idle, ready to go again.
    func dismiss() {
        guard phase == .finished else { return }
        reset()
    }

    // MARK: - Ticking & expiry

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Let the system slide each fire by up to 50 ms so it can coalesce our
        // wakeups with other work instead of waking the CPU on its own schedule.
        // Nothing here is sub-100 ms sensitive: this timer only drives the 1 Hz
        // menu-bar label and notices the zero crossing.
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private var lastWholeSecond: Int = -1
    private func tick() {
        // Drive the menu-bar label at ~1 Hz without redrawing it every 0.2 s.
        let whole = Int(remaining())
        if whole != lastWholeSecond {
            lastWholeSecond = whole
            menuBarTick &+= 1
        }
        checkExpiry()
    }

    /// Fire the finish exactly once when the deadline has passed (covers the case
    /// where the Mac slept straight through zero — we detect it on wake).
    private func checkExpiry() {
        guard phase == .running else { return }
        if remaining() <= 0 {
            fireFinish()
        }
    }

    private func fireFinish() {
        guard phase == .running else { return }
        phase = .finished
        deadline = nil
        frozenRemaining = nil
        stopTicker()
        onFinish?()
    }

    // 2026-08-21: `adopt(snapshot:)` lived here so the app could pick up a countdown
    // the WIDGET had started while it was closed. The widget is gone, this process is
    // the only thing that ever knows about a timer, and launching therefore always
    // starts from a clean idle state (issue #32).

    #if DEBUG
    /// Jump straight to the finished look (for snapshots/tests) without the alarm.
    func debugForceFinish() {
        stopTicker()
        deadline = nil
        frozenRemaining = nil
        phase = .finished
    }
    #endif

    // MARK: - Formatting

    /// "MM:SS" or "H:MM:SS" for long timers. Uses ceil so a fresh 25-min timer
    /// reads 25:00 and lands on 00:00.
    func formatted(_ t: TimeInterval) -> String {
        let total = max(0, Int(ceil(t)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%02d:%02d", m, s)
    }

    /// Localized duration phrasing for VoiceOver ("12 minutes, 30 seconds" etc.) —
    /// the system formatter speaks every app language, unlike hand-built English.
    private static let accessibleFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .full
        f.zeroFormattingBehavior = .dropLeading
        return f
    }()

    /// VoiceOver-friendly phrasing, e.g. "12 minutes, 30 seconds remaining",
    /// in the user's language.
    func accessibleRemaining(_ t: TimeInterval) -> String {
        let total = TimeInterval(max(0, Int(ceil(t))))
        let duration = TimerEngine.accessibleFormatter.string(from: total) ?? formatted(total)
        return String(format: String(localized: "%@ remaining"), duration)
    }
}
