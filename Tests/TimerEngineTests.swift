import XCTest

/// The countdown state machine — every transition the dial, the menu bar and the
/// the UI can trigger.
///
/// These are deterministic because `TimerEngine` derives everything from an
/// absolute deadline and takes the "now" it should measure against
/// (`remaining(at:)`), so a test can look into the future instead of sleeping.
/// Exactly one test below uses real time: the one that proves the live ticker
/// actually fires `onFinish`.
@MainActor
final class TimerEngineTests: XCTestCase {

    private let cap: TimeInterval = 999 * 60   // the picker's ceiling

    // MARK: - Idle & configuration

    func testIdleReportsTheConfiguredDuration() {
        let engine = TimerEngine(durationSeconds: 25 * 60)
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.remaining, 25 * 60, accuracy: 0.001)
        XCTAssertEqual(engine.fractionRemaining(), 1, accuracy: 0.001)
        XCTAssertFalse(engine.isActive)
        XCTAssertNil(engine.runningDeadline)
    }

    func testDurationIsClampedToOneSecondAndTheCeiling() {
        let engine = TimerEngine(durationSeconds: 60)

        engine.setDuration(seconds: 0)
        XCTAssertEqual(engine.configuredDuration, 1, accuracy: 0.001)

        engine.setDuration(seconds: -30)
        XCTAssertEqual(engine.configuredDuration, 1, accuracy: 0.001)

        engine.setDuration(seconds: 10_000 * 60)
        XCTAssertEqual(engine.configuredDuration, cap, accuracy: 0.001)

        engine.setMinutes(25)
        XCTAssertEqual(engine.configuredDuration, 25 * 60, accuracy: 0.001)
    }

    func testInitAlsoClampsAZeroDuration() {
        XCTAssertEqual(TimerEngine(durationSeconds: 0).configuredDuration, 1, accuracy: 0.001)
    }

    // MARK: - Running

    func testStartCountsDownFromTheDeadlineAndNeverGoesNegative() {
        let engine = TimerEngine(durationSeconds: 600)
        let t0 = Date()
        engine.start()

        XCTAssertEqual(engine.phase, .running)
        XCTAssertTrue(engine.isActive)
        XCTAssertNotNil(engine.runningDeadline)

        XCTAssertEqual(engine.remaining(at: t0), 600, accuracy: 0.5)
        XCTAssertEqual(engine.remaining(at: t0.addingTimeInterval(60)), 540, accuracy: 0.5)
        XCTAssertEqual(engine.fractionRemaining(at: t0.addingTimeInterval(300)), 0.5, accuracy: 0.01)

        // Past the deadline the derived values clamp instead of going negative.
        XCTAssertEqual(engine.remaining(at: t0.addingTimeInterval(1200)), 0, accuracy: 0.001)
        XCTAssertEqual(engine.fractionRemaining(at: t0.addingTimeInterval(1200)), 0, accuracy: 0.001)
    }

    /// The picker's floor is 1 second (a 0:00 entry snaps up to it), so the shortest
    /// timer the UI can produce must still be startable.
    func testTheShortestPossibleTimerIsStartable() {
        let engine = TimerEngine(durationSeconds: 1)
        engine.setDuration(seconds: 0)          // clamps to 1
        engine.start()
        XCTAssertEqual(engine.phase, .running)
    }

    // MARK: - Pause / resume

    func testPauseFreezesTheRemainingTimeAgainstThePassageOfTime() {
        let engine = TimerEngine(durationSeconds: 300)
        engine.start()
        engine.pause()

        XCTAssertEqual(engine.phase, .paused)
        XCTAssertTrue(engine.isActive)
        XCTAssertNil(engine.runningDeadline, "a paused timer has no deadline to publish")

        let frozen = engine.remaining
        XCTAssertEqual(frozen, 300, accuracy: 0.5)
        // The whole point of pausing: later "now"s must read the same.
        XCTAssertEqual(engine.remaining(at: Date().addingTimeInterval(120)), frozen, accuracy: 0.001)
        XCTAssertEqual(engine.remaining(at: Date().addingTimeInterval(9_999)), frozen, accuracy: 0.001)
    }

    func testResumeRebuildsTheDeadlineFromTheFrozenRemainder() {
        let engine = TimerEngine(durationSeconds: 300)
        engine.start()
        engine.pause()
        let frozen = engine.remaining

        engine.resume()
        XCTAssertEqual(engine.phase, .running)
        XCTAssertEqual(engine.remaining(at: Date()), frozen, accuracy: 0.5)
        XCTAssertNotNil(engine.runningDeadline)
    }

    func testPauseAndResumeOnlyActFromTheirOwnPhase() {
        let engine = TimerEngine(durationSeconds: 60)

        engine.pause()                                  // idle → no-op
        XCTAssertEqual(engine.phase, .idle)

        engine.resume()                                 // idle → no-op
        XCTAssertEqual(engine.phase, .idle)

        engine.start()
        engine.resume()                                 // running → no-op
        XCTAssertEqual(engine.phase, .running)
    }

    func testPrimaryActionCyclesStartPauseResume() {
        let engine = TimerEngine(durationSeconds: 60)

        engine.primaryAction()
        XCTAssertEqual(engine.phase, .running)
        engine.primaryAction()
        XCTAssertEqual(engine.phase, .paused)
        engine.primaryAction()
        XCTAssertEqual(engine.phase, .running)
    }

    // MARK: - Reset / dismiss

    func testResetReturnsToIdleAtTheLastChosenDuration() {
        let engine = TimerEngine(durationSeconds: 300)
        engine.start()
        engine.reset()

        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.remaining, 300, accuracy: 0.001)
        XCTAssertNil(engine.runningDeadline)
    }

    func testDismissOnlyLeavesTheFinishedState() {
        let engine = TimerEngine(durationSeconds: 60)
        engine.start()
        engine.dismiss()
        XCTAssertEqual(engine.phase, .running, "dismiss must not cancel a live timer")

        // 2026-08-21: this used to reach `.finished` through `adopt(snapshot:)`,
        // which went with the widget. Let a one-second timer finish for real instead
        // — slower, but it exercises the only route to `.finished` that still exists.
        let short = TimerEngine(durationSeconds: 1)
        short.setDuration(seconds: 60)
        short.setDuration(seconds: 1)
        let finished = expectation(description: "onFinish called")
        short.onFinish = { finished.fulfill() }
        short.start()
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(short.phase, .finished)

        short.dismiss()
        XCTAssertEqual(short.phase, .idle)
        XCTAssertEqual(short.remaining, 1, accuracy: 0.001)
    }

    // MARK: - Finishing for real (the one test that uses the wall clock)

    func testOnFinishFiresExactlyOnceWhenTheDeadlinePasses() {
        let engine = TimerEngine(durationSeconds: 1)
        var fireCount = 0
        let finished = expectation(description: "onFinish called")
        engine.onFinish = {
            fireCount += 1
            finished.fulfill()
        }

        engine.start()
        wait(for: [finished], timeout: 5)      // spins the run loop → the 0.2 s ticker runs

        XCTAssertEqual(engine.phase, .finished)
        XCTAssertEqual(engine.remaining, 0, accuracy: 0.001)
        XCTAssertNil(engine.runningDeadline)

        // The ticker is stopped by the finish itself; give it room to misbehave.
        let settled = expectation(description: "no second fire")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertEqual(fireCount, 1, "the alarm must never double-fire")
    }

    // 2026-08-21: five tests for `adopt(snapshot:)` lived here. They covered the
    // widget handing a running countdown to the app — a path that no longer exists,
    // along with the method itself. Nothing else called it.

    // MARK: - Formatting

    func testFormattedRoundsUpAndGrowsAnHoursFieldWhenNeeded() {
        let engine = TimerEngine(durationSeconds: 60)

        XCTAssertEqual(engine.formatted(0), "00:00")
        XCTAssertEqual(engine.formatted(-5), "00:00", "a passed deadline reads zero, not minus")
        XCTAssertEqual(engine.formatted(0.2), "00:01", "ceil: any remainder still shows a second")
        XCTAssertEqual(engine.formatted(59.4), "01:00")
        XCTAssertEqual(engine.formatted(90), "01:30")
        XCTAssertEqual(engine.formatted(25 * 60), "25:00")
        XCTAssertEqual(engine.formatted(3600), "1:00:00")
        XCTAssertEqual(engine.formatted(3661), "1:01:01")
    }

    /// The VoiceOver phrase must be built by the system formatter (so it speaks the
    /// user's language) and must actually substitute the duration into the sentence.
    func testAccessibleRemainingSubstitutesALocalizedDuration() {
        let engine = TimerEngine(durationSeconds: 750)
        let spoken = engine.accessibleRemaining(750)

        XCTAssertFalse(spoken.isEmpty)
        XCTAssertFalse(spoken.contains("%@"), "the format placeholder must be filled in")
        XCTAssertTrue(spoken.contains("12"), "12 minutes 30 seconds — the number must survive")
        XCTAssertTrue(spoken.contains("30"))
    }

    // MARK: - Helpers

}
