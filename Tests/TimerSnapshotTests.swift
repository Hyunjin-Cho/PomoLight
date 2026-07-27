import XCTest
import SwiftUI

/// The App Group snapshot is the ONLY thing the widget process can see, and the
/// widget can be running an old build of the app's data (or vice versa) after an
/// update. So the contract under test is: new optional fields must never break
/// decoding of a snapshot written before they existed.
final class TimerSnapshotTests: XCTestCase {

    func testRoundTripsThroughJSONUnchanged() throws {
        let original = TimerSnapshot(phase: .running,
                                     deadline: Date(timeIntervalSince1970: 1_800_000_000),
                                     remaining: 480,
                                     configuredDuration: 1_500,
                                     fractionRemaining: 0.32,
                                     accentHex: "#E79A86",
                                     updatedAt: Date(timeIntervalSince1970: 1_799_999_000),
                                     alarmSoundFile: "SoftChime.caf",
                                     notificationsEnabled: false,
                                     backupAlarmScheduled: true)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TimerSnapshot.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    /// A snapshot written by the pre-widget-alarm build: none of the three optional
    /// fields are present. It must still decode, with nil standing for "unknown".
    func testLegacySnapshotWithoutTheOptionalFieldsStillDecodes() throws {
        let legacy = """
        {
          "phase": "paused",
          "remaining": 600,
          "configuredDuration": 1500,
          "fractionRemaining": 0.4,
          "accentHex": "#E79A86",
          "updatedAt": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TimerSnapshot.self, from: legacy)

        XCTAssertEqual(decoded.phase, .paused)
        XCTAssertEqual(decoded.remaining, 600, accuracy: 0.001)
        XCTAssertEqual(decoded.configuredDuration, 1_500, accuracy: 0.001)
        XCTAssertNil(decoded.deadline)
        XCTAssertNil(decoded.alarmSoundFile)
        XCTAssertNil(decoded.notificationsEnabled,
                     "nil is read as 'notifications enabled' — the old behavior")
        XCTAssertNil(decoded.backupAlarmScheduled,
                     "nil means 'not applicable', which is why the badge only shows on false")
    }

    func testEveryPhaseSurvivesTheStringRepresentation() throws {
        for phase in [TimerSnapshot.Phase.idle, .running, .paused, .finished] {
            var snap = TimerSnapshot.placeholder
            snap.phase = phase
            let decoded = try JSONDecoder().decode(TimerSnapshot.self,
                                                   from: try JSONEncoder().encode(snap))
            XCTAssertEqual(decoded.phase, phase)
        }
    }

    func testPlaceholderIsAFullIdleTimer() {
        let p = TimerSnapshot.placeholder
        XCTAssertEqual(p.phase, .idle)
        XCTAssertNil(p.deadline)
        XCTAssertEqual(p.fractionRemaining, 1, accuracy: 0.001)
        XCTAssertEqual(p.remaining, p.configuredDuration, accuracy: 0.001)
    }

    /// The widget renders these strings, so they must match the app's dial exactly.
    func testFormattedMatchesTheAppsRoundingAndHoursHandling() {
        let snap = TimerSnapshot.placeholder

        XCTAssertEqual(snap.formatted(0), "00:00")
        XCTAssertEqual(snap.formatted(-5), "00:00")
        XCTAssertEqual(snap.formatted(0.2), "00:01")
        XCTAssertEqual(snap.formatted(59.4), "01:00")
        XCTAssertEqual(snap.formatted(90), "01:30")
        XCTAssertEqual(snap.formatted(3600), "1:00:00")
        XCTAssertEqual(snap.formatted(3661), "1:01:01")
    }

    /// The widget parses the accent out of the snapshot with its own tiny hex reader
    /// (it can't see the app's `RGB`), so the two must agree — including on junk.
    func testTheWidgetsHexReaderAgreesWithTheApps() {
        for hex in ["#E79A86", "E79A86", "#abc", "#000000", "#FFFFFF"] {
            let appSide = RGB(hex: hex)
            let widgetSide = Color(appHex: hex)
            XCTAssertEqual(widgetSide, appSide.color, "disagreed on \(hex)")
        }
    }
}
