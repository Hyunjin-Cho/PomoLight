import XCTest

// MARK: - Recorders
//
// Each one stands in for a part that reaches hardware and remembers only what it
// was told to do. Nothing here plays a sound, asks for a permission, holds the Mac
// awake or moves a window.

@MainActor
private final class SpyAlarm: AlarmPlaying {
    struct Ring: Equatable { let sound: AlarmSound; let volume: Double; let repeats: Bool }
    private(set) var rings: [Ring] = []
    private(set) var previews: [Ring] = []
    private(set) var stopCount = 0
    var onRing: (() -> Void)?

    func playAlarm(sound: AlarmSound, volume: Double, repeatUntilDismissed: Bool) {
        rings.append(Ring(sound: sound, volume: volume, repeats: repeatUntilDismissed))
        onRing?()
    }
    func preview(sound: AlarmSound, volume: Double) {
        previews.append(Ring(sound: sound, volume: volume, repeats: false))
    }
    func stop() { stopCount += 1 }
}

@MainActor
private final class SpyNotifier: FinishNotifying {
    private(set) var delegateConfigured = 0
    private(set) var permissionRequests = 0
    private(set) var deliveries: [Bool] = []      // the `enabled` flag each time

    func configureDelegate() { delegateConfigured += 1 }
    func requestAuthorizationIfNeeded() { permissionRequests += 1 }
    func notifyTimerFinished(enabled: Bool) { deliveries.append(enabled) }
}

@MainActor
private final class SpySleepKeeper: SleepPreventing {
    private(set) var calls: [Bool] = []
    func setActive(_ active: Bool) { calls.append(active) }
}

@MainActor
private final class SpyWindowRaiser: WindowRaising {
    private(set) var raiseCount = 0
    func bringToFront() { raiseCount += 1 }
}

/// The end-of-timer wiring: `TimerEngine.onFinish` fires and four separate things
/// have to happen. Until 2026-08-21 none of it was covered — `AppModel` built its
/// own collaborators, so a test could not watch them without also making noise.
///
/// The timers here are one second of real time, because that is the only route to
/// `.finished` that still exists (the widget's `adopt(snapshot:)` went with the
/// widget). Every test drives a throwaway defaults suite, so the owner's own
/// preferences are never read or written.
@MainActor
final class AppModelFinishTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var alarm: SpyAlarm!
    private var notifier: SpyNotifier!
    private var sleepKeeper: SpySleepKeeper!
    private var windows: SpyWindowRaiser!

    override func setUp() {
        super.setUp()
        suiteName = "pl.finishtests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        alarm = SpyAlarm()
        notifier = SpyNotifier()
        sleepKeeper = SpySleepKeeper()
        windows = SpyWindowRaiser()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil; suiteName = nil
        alarm = nil; notifier = nil; sleepKeeper = nil; windows = nil
        super.tearDown()
    }

    private func makeModel() -> AppModel {
        AppModel(defaults: defaults, chime: alarm, notifications: notifier,
                 power: sleepKeeper, windows: windows)
    }

    /// Run a one-second timer to completion and return the model.
    private func runATimerToTheEnd(_ app: AppModel,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let rang = expectation(description: "the alarm was asked to ring")
        alarm.onRing = { rang.fulfill() }
        app.engine.setDuration(seconds: 1)
        app.startTimer()
        wait(for: [rang], timeout: 5)
        XCTAssertEqual(app.engine.phase, .finished, file: file, line: line)
    }

    // MARK: - The wiring itself

    /// The one that matters: all four effects, from one finish. Delete any single
    /// line of `handleFinish()` and exactly one of these assertions fails.
    func testFinishingRingsNotifiesRaisesTheWindowAndHandsBackSleep() {
        defaults.set(true, forKey: "pl.keepAwake")
        let app = makeModel()
        runATimerToTheEnd(app)

        XCTAssertEqual(alarm.rings.count, 1, "the alarm must ring exactly once")
        XCTAssertEqual(notifier.deliveries.count, 1, "the backup banner must be posted")
        XCTAssertEqual(windows.raiseCount, 1, "the window must come forward")
        XCTAssertEqual(sleepKeeper.calls.last, false,
                       "a finished timer hands sleep back — otherwise a Mac with " +
                       "keep-awake on never sleeps again until the app is quit")
    }

    /// The alarm is rung with what the user chose, not with defaults baked in here.
    func testTheAlarmIsRungWithTheStoredSoundVolumeAndRepeatSetting() {
        defaults.set(AlarmSound.marimba.rawValue, forKey: "pl.alarmSound")
        defaults.set(0.42, forKey: "pl.alarmVolume")
        defaults.set(true, forKey: "pl.repeatUntilDismissed")

        let app = makeModel()
        runATimerToTheEnd(app)

        XCTAssertEqual(alarm.rings.first,
                       SpyAlarm.Ring(sound: .marimba, volume: 0.42, repeats: true))
    }

    /// "Notifications" in the settings panel has to reach the delivery call. The
    /// manager itself is what decides to stay quiet, so the flag must arrive as-is.
    func testTheNotificationCarriesTheUsersToggle() {
        defaults.set(false, forKey: "pl.notificationsEnabled")
        let app = makeModel()
        runATimerToTheEnd(app)
        XCTAssertEqual(notifier.deliveries, [false])
    }

    // MARK: - Silencing

    func testResetAndDismissBothSilenceARingingAlarm() {
        let app = makeModel()
        runATimerToTheEnd(app)
        XCTAssertEqual(alarm.stopCount, 0, "nothing has asked for silence yet")

        app.dismissFinished()
        XCTAssertEqual(alarm.stopCount, 1, "Dismiss must stop a repeating alarm")

        // Reset from a live timer has to silence it too — "repeat until dismissed"
        // keeps ringing on a schedule of its own otherwise.
        app.engine.setDuration(seconds: 600)
        app.startTimer()
        app.resetTimer()
        XCTAssertEqual(alarm.stopCount, 2)
    }

    // MARK: - Launch

    /// Permission is asked once, at launch, on purpose — see `AppModel.init`. This
    /// pins the count as well as the fact: a second asker was removed on 2026-08-21
    /// because two of them could race and both see `.notDetermined`.
    func testLaunchWiresTheNotificationDelegateAndAsksForPermissionExactlyOnce() {
        let app = makeModel()
        XCTAssertEqual(notifier.delegateConfigured, 1)
        XCTAssertEqual(notifier.permissionRequests, 1)

        app.engine.setDuration(seconds: 600)
        app.startTimer()
        XCTAssertEqual(notifier.permissionRequests, 1, "starting a timer must not ask again")
    }

    // MARK: - Sleep assertion

    func testSleepIsHeldOnlyWhileRunningAndOnlyWhenTheUserAskedForIt() {
        defaults.set(true, forKey: "pl.keepAwake")
        let app = makeModel()
        app.engine.setDuration(seconds: 600)

        app.startTimer()
        XCTAssertEqual(sleepKeeper.calls.last, true, "a running timer holds the Mac awake")

        app.primaryAction()                       // running → paused
        XCTAssertEqual(app.engine.phase, .paused)
        XCTAssertEqual(sleepKeeper.calls.last, false, "a paused timer must not hold it")

        app.primaryAction()                       // paused → running
        XCTAssertEqual(sleepKeeper.calls.last, true)

        app.resetTimer()
        XCTAssertEqual(sleepKeeper.calls.last, false)
    }

    func testSleepIsNeverHeldWhenKeepAwakeIsOff() {
        let app = makeModel()                     // keepAwake defaults to false
        app.engine.setDuration(seconds: 600)
        app.startTimer()
        XCTAssertFalse(sleepKeeper.calls.contains(true),
                       "keep-awake is off, so nothing may hold the system awake")
    }

    // MARK: - Duration restore

    // 2026-11-20 (#67): 여기 있던 `testDismissingReturnsToTheStoredDurationNotTheOneThatJustRan`
    // 은 "엔진에 넣고 돌린 시간이 저장값을 바꾸면 안 된다"를 계약으로 박아 두고 있었다.
    // 그 계약이 바로 #67 의 버그였다 — 대기 상태에서 엔진 시간을 바꾸는 건 시간 고르기
    // 화면뿐이라, "엔진에 넣었지만 저장 안 된 시간"은 실제로는 "직접 입력하고 포커스를
    // 둔 채 시작한 시간"이다. 아래 세 시험이 새 계약이다.

    /// The #67 case, as the picker leaves it: the custom entry has pushed 17 minutes
    /// into the engine but, with a field still focused, has not saved it. Start →
    /// Reset must come back to 17, not to the 15 saved earlier.
    func testResetAfterStartingAnUnsavedCustomDurationKeepsThatDuration() {
        defaults.set(15.0, forKey: "pl.lastDurationMinutes")
        let app = makeModel()
        app.engine.setDuration(seconds: 17 * 60)     // what pushToEngine() does

        app.startTimer()
        app.resetTimer()

        XCTAssertEqual(app.engine.configuredDuration, 17 * 60, accuracy: 0.001,
                       "reset must not fall back to the duration saved before")
        XCTAssertEqual(app.settings.lastDurationMinutes, 17, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: "pl.lastDurationMinutes"), 17, accuracy: 0.001,
                       "and it has to reach the preferences, so the next launch has it too")
    }

    /// The other exit from a run: finishing and dismissing. Same duration back.
    func testDismissingAfterAFinishReturnsToTheDurationThatWasStarted() {
        defaults.set(25.0, forKey: "pl.lastDurationMinutes")
        let app = makeModel()
        XCTAssertEqual(app.engine.configuredDuration, 25 * 60, accuracy: 0.001)

        runATimerToTheEnd(app)                    // chosen and started: one second
        app.dismissFinished()

        XCTAssertEqual(app.engine.configuredDuration, 1, accuracy: 0.001)
        XCTAssertEqual(app.settings.lastDurationMinutes, 1.0 / 60, accuracy: 0.0001)
    }

    /// Starting with the duration that is already saved must not write at all —
    /// the point of #46 was to keep needless writes off the preferences file.
    func testStartingWithTheSavedDurationDoesNotWriteIt() {
        defaults.set(25.0, forKey: "pl.lastDurationMinutes")
        let app = makeModel()
        defaults.removeObject(forKey: "pl.lastDurationMinutes")   // a write would put it back

        app.startTimer()

        // Read the suite's own file, not `object(forKey:)`: SettingsStore registers a
        // 30-minute default, and the registration domain would answer for it.
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["pl.lastDurationMinutes"],
                     "an unchanged duration was written again")
    }

    // MARK: - Preview

    /// The settings panel auditions a sound at the user's volume, and an audition
    /// must not be mistaken for the alarm going off.
    func testAuditioningASoundUsesTheStoredVolumeAndIsNotAnAlarm() {
        defaults.set(0.3, forKey: "pl.alarmVolume")
        let app = makeModel()

        app.preview(.handpan)

        XCTAssertEqual(app.settings.alarmVolume, 0.3, accuracy: 0.001)
        XCTAssertEqual(alarm.previews, [SpyAlarm.Ring(sound: .handpan, volume: 0.3, repeats: false)])
        XCTAssertTrue(alarm.rings.isEmpty)
        XCTAssertEqual(windows.raiseCount, 0)
    }
}
