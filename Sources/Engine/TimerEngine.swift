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

    init(durationSeconds: TimeInterval) {
        self.configuredDuration = max(1, durationSeconds)
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

    /// The absolute end time while running (nil otherwise) — lets the widget run a
    /// self-ticking countdown without constant timeline reloads.
    var runningDeadline: Date? { phase == .running ? deadline : nil }

    // MARK: - Configuration

    /// Set the duration (only meaningful when not actively counting). Resets to idle.
    func setDuration(seconds: TimeInterval) {
        let clamped = min(max(1, seconds), 999 * 60)
        configuredDuration = clamped
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

    /// Adds one minute of focus, working while running, paused, or idle. Honors
    /// the same 999-minute ceiling as the picker.
    func addMinute() {
        let cap: TimeInterval = 999 * 60
        let bump: TimeInterval = 60
        switch phase {
        case .running:
            let newDuration = min(configuredDuration + bump, cap)
            let applied = newDuration - configuredDuration
            deadline = (deadline ?? Date()).addingTimeInterval(applied)
            configuredDuration = newDuration
        case .paused:
            let newDuration = min(configuredDuration + bump, cap)
            let applied = newDuration - configuredDuration
            frozenRemaining = (frozenRemaining ?? 0) + applied
            configuredDuration = newDuration
        case .idle:
            setDuration(seconds: configuredDuration + bump)
        case .finished:
            break   // +1 is only offered while running/paused/idle
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

    /// Adopt a state change made by the WIDGET (via the shared snapshot). Mirrors
    /// the widget's intent into the live engine so both stay in lockstep; if the
    /// widget-started timer already expired, the normal finish path fires (chime).
    func adopt(snapshot: TimerSnapshot) {
        switch snapshot.phase {
        case .running:
            guard let d = snapshot.deadline else { return }
            configuredDuration = max(1, snapshot.configuredDuration)
            if d.timeIntervalSinceNow <= 0 {
                // Expired while the app wasn't watching (e.g. widget-started timer,
                // app launched later): show the finished state QUIETLY. Calling the
                // full finish path here would touch NSApp during App.main() startup
                // and crash — and the moment has passed anyway.
                deadline = nil
                frozenRemaining = nil
                stopTicker()
                phase = .finished
                return
            }
            deadline = d
            frozenRemaining = nil
            phase = .running
            startTicker()
        case .paused:
            configuredDuration = max(1, snapshot.configuredDuration)
            frozenRemaining = max(0, snapshot.remaining)
            deadline = nil
            phase = .paused
            stopTicker()
        case .idle:
            stopTicker()
            deadline = nil
            frozenRemaining = nil
            configuredDuration = max(1, snapshot.configuredDuration)
            phase = .idle
        case .finished:
            stopTicker()
            deadline = nil
            frozenRemaining = nil
            phase = .finished
        }
    }

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

    /// VoiceOver-friendly phrasing, e.g. "12 minutes 30 seconds remaining".
    func accessibleRemaining(_ t: TimeInterval) -> String {
        let total = max(0, Int(ceil(t)))
        let m = total / 60, s = total % 60
        var parts: [String] = []
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        parts.append("\(s) second\(s == 1 ? "" : "s")")
        return parts.joined(separator: " ") + " remaining"
    }
}
