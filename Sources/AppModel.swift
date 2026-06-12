import SwiftUI
import Observation
import WidgetKit
import UserNotifications

/// The top-level object graph. Owns the timer, theme, settings, audio, and
/// notifications, and wires the "timer finished" behavior together in one place.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let theme: ThemeStore
    let engine: TimerEngine

    @ObservationIgnored let chime = ChimePlayer()
    @ObservationIgnored let notifications = NotificationManager()
    @ObservationIgnored private let power = PowerAssertion()

    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.theme = ThemeStore(settings: settings)
        self.engine = TimerEngine(durationSeconds: settings.lastDurationMinutes * 60)

        engine.onFinish = { [weak self] in self?.handleFinish() }
        notifications.configureDelegate()

        // If the WIDGET drove the timer while the app was closed (interactive
        // buttons), pick that state up on launch instead of clobbering it.
        let snap = SharedStore.read()
        if snap.phase == .running || snap.phase == .paused {
            engine.adopt(snapshot: snap)
            // The live app owns the alarm again — drop any backup notification.
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["pl.widget.finish"])
        }
        observeWidgetChanges()
        publishSnapshot()
    }

    /// Live sync: widget intents post a Darwin notification after mutating the
    /// shared snapshot; adopt it immediately so the open app mirrors the widget.
    private func observeWidgetChanges() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let model = Unmanaged<AppModel>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in model.adoptWidgetState() }
        }, SharedStore.widgetChangeNote as CFString, nil, .deliverImmediately)
    }

    private func adoptWidgetState() {
        let snap = SharedStore.read()
        engine.adopt(snapshot: snap)
        if engine.phase != .finished { chime.stop() }   // widget dismissed/reset the alarm
        if engine.phase == .running {
            // The live app owns the alarm now — drop the widget's backup notification.
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ["pl.widget.finish"])
        }
        updatePowerAssertion()
    }

    // MARK: - Actions used by the views

    /// Start the timer. We do NOT persist the duration here — otherwise a session
    /// extended with "+1 min" would silently become the next launch's default.
    /// The chosen duration is saved only when the user explicitly picks it
    /// (preset chip / custom entry). Also requests notification permission in
    /// context, so the first finish can actually deliver a banner.
    func startTimer() {
        notifications.requestAuthorizationIfNeeded()
        engine.start()
        sync()
    }

    func primaryAction() {
        switch engine.phase {
        case .idle:     startTimer()
        case .running:  engine.pause();  sync()
        case .paused:   engine.resume(); sync()
        case .finished: dismissFinished()
        }
    }

    func resetTimer() {
        chime.stop()
        engine.reset()
        restoreChosenDuration()
        sync()
    }

    func dismissFinished() {
        chime.stop()
        engine.dismiss()
        restoreChosenDuration()
        sync()
    }

    /// After a reset/dismiss, return to the user's explicitly-chosen duration so an
    /// in-session "+1 min" extension doesn't linger into the next run.
    private func restoreChosenDuration() {
        engine.setDuration(seconds: settings.lastDurationMinutes * 60)
    }

    func addMinute() {
        engine.addMinute()
        if engine.phase == .idle {
            settings.lastDurationMinutes = engine.configuredDuration / 60
        }
        sync()
    }

    /// Call after any state change: keep the sleep assertion and the widget's
    /// shared snapshot in step with the engine.
    private func sync() {
        updatePowerAssertion()
        publishSnapshot()
    }

    /// Publishes the timer state to the App Group and refreshes the widget.
    func publishSnapshot() {
        let phase: TimerSnapshot.Phase
        switch engine.phase {
        case .idle:     phase = .idle
        case .running:  phase = .running
        case .paused:   phase = .paused
        case .finished: phase = .finished
        }
        let snapshot = TimerSnapshot(
            phase: phase,
            deadline: engine.runningDeadline,
            remaining: engine.remaining(),
            configuredDuration: engine.configuredDuration,
            fractionRemaining: engine.fractionRemaining(),
            accentHex: theme.current.light.accent,
            updatedAt: Date())
        SharedStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func previewSound() {
        chime.preview(sound: settings.alarmSound, volume: settings.alarmVolume)
    }

    func preview(_ sound: AlarmSound) {
        chime.preview(sound: sound, volume: settings.alarmVolume)
    }

    // MARK: - Finish

    private func handleFinish() {
        chime.playAlarm(sound: settings.alarmSound,
                        volume: settings.alarmVolume,
                        repeatUntilDismissed: settings.repeatUntilDismissed)
        notifications.notifyTimerFinished(enabled: settings.notificationsEnabled)
        AppActivation.bringToFront()
        sync()
    }

    private func updatePowerAssertion() {
        power.setActive(settings.keepAwake && engine.phase == .running)
    }
}
