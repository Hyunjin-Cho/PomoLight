import SwiftUI
import Observation

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

    // 🚨 2026-08-21: the widget is gone, and with it every reason this class had to
    // talk to anything outside the process. What used to live here:
    //   · an App Group snapshot published on every state change, so the widget could
    //     draw the countdown;
    //   · a Darwin-notification observer, so widget button presses reached a running
    //     app instantly;
    //   · adopting that snapshot at launch, so a widget-started timer was not
    //     clobbered by the app opening later.
    // The last one is why quitting and relaunching used to resurrect a countdown
    // instead of showing a fresh screen — the app could not tell "the widget started
    // this" from "I crashed while running this", because the snapshot said the same
    // thing either way (issue #32). With no second writer, there is nothing to adopt:
    // launching always starts fresh, which is what it should have looked like all
    // along. See also #29 — the widget's own end-of-timer notification is gone too,
    // so no alarm can outlive the process any more.
    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.theme = ThemeStore(settings: settings)
        self.engine = TimerEngine(durationSeconds: settings.lastDurationMinutes * 60)

        engine.onFinish = { [weak self] in self?.handleFinish() }
        notifications.configureDelegate()
        // Asked at launch rather than at the first start so the very first finish
        // can deliver its banner without a permission prompt landing on top of it.
        notifications.requestAuthorizationIfNeeded()

        observeSettingChanges()
        updatePowerAssertion()
    }

    /// Settings can change outside any timer action (panel toggles, theme swatch),
    /// and the sleep assertion has to follow. Watch the relevant properties so a
    /// mid-session change applies immediately, not on the next timer action.
    /// (`withObservationTracking` is one-shot, so the handler re-arms.)
    private func observeSettingChanges() {
        withObservationTracking {
            _ = settings.keepAwake
            _ = theme.current
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updatePowerAssertion()
                self.observeSettingChanges()
            }
        }
    }

    // MARK: - Actions used by the views

    /// Start the timer. We do NOT persist the duration here — otherwise a session
    /// extended mid-run would silently become the next launch's default. The chosen
    /// duration is saved only when the user explicitly picks it (preset chip /
    /// custom entry). Also requests notification permission in context, so the first
    /// finish can actually deliver a banner.
    func startTimer() {
        notifications.requestAuthorizationIfNeeded()
        engine.start()
        updatePowerAssertion()
    }

    func primaryAction() {
        switch engine.phase {
        case .idle:     startTimer()
        case .running:  engine.pause();  updatePowerAssertion()
        case .paused:   engine.resume(); updatePowerAssertion()
        case .finished: dismissFinished()
        }
    }

    func resetTimer() {
        chime.stop()
        engine.reset()
        restoreChosenDuration()
        updatePowerAssertion()
    }

    func dismissFinished() {
        chime.stop()
        engine.dismiss()
        restoreChosenDuration()
        updatePowerAssertion()
    }

    /// After a reset/dismiss, return to the user's explicitly-chosen duration so an
    /// in-session extension doesn't linger into the next run.
    private func restoreChosenDuration() {
        engine.setDuration(seconds: settings.lastDurationMinutes * 60)
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
        updatePowerAssertion()
    }

    private func updatePowerAssertion() {
        power.setActive(settings.keepAwake && engine.phase == .running)
    }
}
