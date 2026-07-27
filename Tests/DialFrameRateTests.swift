import XCTest

/// The dial's redraw cadence is the app's single biggest running cost (30 fps
/// measured 11.25% of a CPU core; 2 fps 2.38%) AND the thing a user notices first if
/// it's too low — a 2 fps ring visibly steps on a 1-minute timer. That trade-off is
/// resolved by one rule, so the rule gets tests.
final class DialFrameRateTests: XCTestCase {

    private let dial = 222.0            // the default window's dial, in points
    private let circumference = Double.pi * 222.0

    // MARK: - The ladder

    func testAShortTimerGetsTheFastestRate() {
        // 44 s and 1 min are the cases the owner saw stepping at 2 fps.
        XCTAssertEqual(DialFrameRate.rate(dialDiameter: dial, duration: 44), 30)
        XCTAssertEqual(DialFrameRate.rate(dialDiameter: dial, duration: 60), 30)
    }

    func testALongTimerGetsTheSlowestRate() {
        for duration in [15.0 * 60, 25.0 * 60, 45.0 * 60, 999.0 * 60] {
            XCTAssertEqual(DialFrameRate.rate(dialDiameter: dial, duration: duration), 2,
                           "\(Int(duration / 60)) min should not need more than 2 fps")
        }
    }

    func testMidLengthTimersLandOnTheMiddleRungs() {
        XCTAssertEqual(DialFrameRate.rate(dialDiameter: dial, duration: 3 * 60), 12)
        XCTAssertEqual(DialFrameRate.rate(dialDiameter: dial, duration: 10 * 60), 6)
    }

    func testOnlyRatesFromTheClosedSetAreEverReturned() {
        for seconds in stride(from: 1.0, through: 999 * 60, by: 7) {
            let rate = DialFrameRate.rate(dialDiameter: dial, duration: seconds)
            XCTAssertTrue(DialFrameRate.rates.contains(rate),
                          "\(seconds)s produced \(rate) fps, which nobody has measured")
        }
    }

    // MARK: - The rule the ladder comes from

    /// The whole point: whatever rate is chosen, the ring must not jump more than half
    /// a point between frames — unless it's already at the fastest rate on offer.
    func testTheChosenRateKeepsTheRingStepWithinHalfAPoint() {
        for seconds in stride(from: 5.0, through: 999 * 60, by: 5) {
            let rate = DialFrameRate.rate(dialDiameter: dial, duration: seconds)
            let step = (circumference / seconds) / rate
            if rate < DialFrameRate.rates.last! {
                XCTAssertLessThanOrEqual(step, DialFrameRate.maxStepPoints + 0.0001,
                                         "\(seconds)s at \(rate) fps steps \(step) pt")
            }
        }
    }

    /// A timer that runs longer moves the ring slower, so it must never ask for MORE
    /// frames than a shorter one.
    func testRateNeverRisesAsTheTimerGetsLonger() {
        var previous = DialFrameRate.rate(dialDiameter: dial, duration: 1)
        for seconds in stride(from: 2.0, through: 999 * 60, by: 3) {
            let rate = DialFrameRate.rate(dialDiameter: dial, duration: seconds)
            XCTAssertLessThanOrEqual(rate, previous, "rate went up at \(seconds)s")
            previous = rate
        }
    }

    /// A bigger dial means a longer ring at the same duration — more distance per
    /// second, so it may need more frames, never fewer. (This is why the rule takes
    /// the diameter instead of hardcoding a rate: the window is resizable.)
    func testABiggerDialNeverAsksForFewerFrames() {
        for seconds in [60.0, 180, 600, 1500] {
            var previous = DialFrameRate.rate(dialDiameter: 180, duration: seconds)
            for diameter in stride(from: 190.0, through: 360, by: 10) {
                let rate = DialFrameRate.rate(dialDiameter: diameter, duration: seconds)
                XCTAssertGreaterThanOrEqual(rate, previous,
                                            "\(diameter) pt dial at \(seconds)s asked for less")
                previous = rate
            }
        }
    }

    // MARK: - Degenerate input

    func testGarbageInputStillProducesAUsableInterval() {
        for (diameter, duration) in [(0.0, 0.0), (-100, -100), (0, 1500), (222, 0)] {
            let interval = DialFrameRate.interval(dialDiameter: diameter, duration: duration)
            XCTAssertTrue(interval > 0 && interval <= 0.5,
                          "diameter \(diameter), duration \(duration) → \(interval)")
        }
    }

    func testIntervalIsTheReciprocalOfTheRate() {
        for seconds in [30.0, 60, 200, 700, 1500] {
            XCTAssertEqual(DialFrameRate.interval(dialDiameter: dial, duration: seconds),
                           1 / DialFrameRate.rate(dialDiameter: dial, duration: seconds),
                           accuracy: 1e-12)
        }
    }
}
