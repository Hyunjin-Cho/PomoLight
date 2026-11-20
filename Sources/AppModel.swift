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
    /// Whether the settings sheet is up. Here rather than in `RootView` so the menu-bar
    /// popover can open it too (2026-11-20 #73: "a new version is available" leads there).
    var showSettings = false

    // 2026-08-21: these were `= ChimePlayer()` etc., built in place. They are now
    // taken as protocols (see FinishEffects.swift) so the finish wiring can be
    // tested without opening the audio device or asking the real notification
    // centre for permission. Nothing outside this class ever touched them, so they
    // are private now too. The defaults are the real parts — every caller that
    // wrote `AppModel()` still gets exactly the app it got before.
    @ObservationIgnored private let chime: AlarmPlaying
    @ObservationIgnored private let notifications: FinishNotifying
    @ObservationIgnored private let power: SleepPreventing
    @ObservationIgnored private let windows: WindowRaising

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
    /// `defaults` is injectable for the same reason the collaborators are: a test
    /// (or a snapshot run) must never read or write the real preferences. See the
    /// note on `Snapshot.render` — a snapshot pass once left the owner's app stuck
    /// on the last theme it rendered.
    init(defaults: UserDefaults = .standard,
         chime: AlarmPlaying? = nil,
         notifications: FinishNotifying? = nil,
         power: SleepPreventing? = nil,
         windows: WindowRaising? = nil) {
        let settings = SettingsStore(defaults: defaults)
        self.settings = settings
        self.theme = ThemeStore(settings: settings)
        self.engine = TimerEngine(durationSeconds: settings.lastDurationMinutes * 60)
        // `?? Real()` rather than a default argument: the real part is then never
        // even constructed when a substitute was supplied, so a test cannot
        // accidentally build an AVAudioEngine on its way to not using one.
        let notifications = notifications ?? NotificationManager()
        self.chime = chime ?? ChimePlayer()
        self.notifications = notifications
        self.power = power ?? PowerAssertion()
        self.windows = windows ?? SystemWindowRaiser()

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

    /// Start the timer, and remember the duration it starts with.
    ///
    /// 2026-11-20 (#67): 예전에는 "여기서는 저장하지 않는다 — 실행 중에 늘린 시간이
    /// 다음 실행의 기본값이 되면 안 된다"고 적혀 있었다. 실행 중에 시간을 늘리는 기능은
    /// 이제 없고, 대기 상태의 엔진 시간을 바꾸는 길은 시간 고르기 화면(프리셋·직접 입력)과
    /// `restoreChosenDuration()` 둘뿐이다. 그래서 시작하는 순간 엔진이 쥔 시간이 곧
    /// 사용자가 고른 시간이다. 직접 입력은 키 하나마다 쓰지 않으려고(#46) 저장을
    /// "포커스가 빠질 때"로 미뤘는데, 포커스를 둔 채 시작하면 그 순간이 오지 않아
    /// 리셋·끄기 뒤 옛 값으로 돌아갔다. 시작은 모든 길이 지나는 한 곳이라 여기서 한 번
    /// 저장한다. 값이 같으면 쓰지 않는다.
    ///
    /// 2026-08-21: this used to call `requestAuthorizationIfNeeded()` as well. Once
    /// `AppModel.init` asks at launch the status is never `.notDetermined` again
    /// (`requestAuthorization` always resolves to granted or denied), so the second
    /// call could only ever be a no-op — and if it did race the launch request, both
    /// would see `.notDetermined` at once. One asker, at one moment.
    func startTimer() {
        let chosenMinutes = engine.configuredDuration / 60
        // 저장값 × 60 ÷ 60 이 부동소수 끝자리에서 어긋날 수 있어 같음을 허용오차로 본다.
        if abs(settings.lastDurationMinutes - chosenMinutes) > 1e-9 {
            settings.lastDurationMinutes = chosenMinutes
        }
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
        windows.bringToFront()
        // Releasing the assertion is part of finishing, not an afterthought: the
        // phase is `.finished` by now, so this hands sleep back. Miss it and a Mac
        // with "keep awake" on never sleeps again until the app is quit.
        updatePowerAssertion()
    }

    private func updatePowerAssertion() {
        power.setActive(settings.keepAwake && engine.phase == .running)
    }
}
