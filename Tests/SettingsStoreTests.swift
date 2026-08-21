import XCTest

/// The persistence layer — added 2026-08-21.
///
/// `SettingsStore` had no tests at all, which is uncomfortable given its history:
/// this is the class behind the two settings accidents this project has actually
/// had (the snapshot run that overwrote the user's theme, and the sandbox change
/// that moved the whole container and silently wiped every preference). It is also
/// the easiest thing here to test, because `init(defaults:)` already takes the
/// store to read and write — no protocol extraction, no stubs.
///
/// Every test runs against a throwaway suite, so a run can never touch the real
/// `com.vismo.pomolight` preferences.
@MainActor
final class SettingsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "pl.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    /// A first launch must produce the documented defaults, not zeroes. `bool(forKey:)`
    /// and `double(forKey:)` return false/0 for anything unregistered, so a dropped
    /// `register(defaults:)` entry would silently mean "0 minutes, muted, no menu bar".
    func testAFreshStoreStartsFromTheRegisteredDefaultsNotZero() {
        let s = SettingsStore(defaults: defaults)

        XCTAssertEqual(s.lastDurationMinutes, 30, accuracy: 0.001)
        XCTAssertEqual(s.selectedThemeID, "coral")
        XCTAssertEqual(s.alarmSound, .synthBell)
        XCTAssertEqual(s.alarmVolume, 0.7, accuracy: 0.001)
        XCTAssertFalse(s.repeatUntilDismissed)
        XCTAssertTrue(s.showInMenuBar, "the menu bar is on out of the box")
        XCTAssertFalse(s.keepAwake)
        XCTAssertFalse(s.showSeconds)
        XCTAssertTrue(s.notificationsEnabled)
    }

    /// The whole point of the class: what the user picks survives a relaunch.
    func testEverySettingSurvivesANewStoreOverTheSameDefaults() {
        let first = SettingsStore(defaults: defaults)
        first.lastDurationMinutes = 12.5
        first.selectedThemeID = "violet"
        first.alarmSound = .marimba
        first.alarmVolume = 0.25
        first.repeatUntilDismissed = true
        first.showInMenuBar = false
        first.keepAwake = true
        first.showSeconds = true
        first.notificationsEnabled = false

        let reopened = SettingsStore(defaults: defaults)   // stands in for a relaunch

        XCTAssertEqual(reopened.lastDurationMinutes, 12.5, accuracy: 0.001)
        XCTAssertEqual(reopened.selectedThemeID, "violet")
        XCTAssertEqual(reopened.alarmSound, .marimba)
        XCTAssertEqual(reopened.alarmVolume, 0.25, accuracy: 0.001)
        XCTAssertTrue(reopened.repeatUntilDismissed)
        XCTAssertFalse(reopened.showInMenuBar)
        XCTAssertTrue(reopened.keepAwake)
        XCTAssertTrue(reopened.showSeconds)
        XCTAssertFalse(reopened.notificationsEnabled)
    }

    /// A stored sound that no longer exists (an old build's rawValue, or a hand-edited
    /// plist) must land on a real voice rather than leaving the alarm unresolvable.
    func testAnUnknownStoredAlarmSoundFallsBackToTheDefaultVoice() {
        defaults.set("theremin", forKey: "pl.alarmSound")
        XCTAssertEqual(SettingsStore(defaults: defaults).alarmSound, .synthBell)
    }

    /// Every `AlarmSound` must round-trip through its rawValue — `synthBell` in
    /// particular keeps a legacy rawValue on purpose, and renaming the case would
    /// otherwise reset everyone's choice on the next launch without a sound.
    func testEveryAlarmSoundRoundTripsThroughItsStoredRawValue() {
        for sound in AlarmSound.allCases {
            let writer = SettingsStore(defaults: defaults)
            writer.alarmSound = sound
            XCTAssertEqual(SettingsStore(defaults: defaults).alarmSound, sound,
                           "\(sound.rawValue) did not survive a round trip")
        }
    }

    /// Not a check that the accounts are the owner's — that is issue #6 and a human
    /// has to open them. This only pins that whatever ends up in the table is a URL
    /// the app can actually open: `DonateButton` does `URL(string:)` and, on nil,
    /// does nothing at all, so a typo would make the heart button dead in silence.
    func testEveryDonationLinkIsAnOpenableHTTPSURL() {
        XCTAssertFalse(SettingsStore.donationLinks.isEmpty)
        for link in SettingsStore.donationLinks {
            let url = URL(string: link.urlString)
            XCTAssertNotNil(url, "\(link.id): \(link.urlString) is not a URL")
            XCTAssertEqual(url?.scheme, "https", "\(link.id) must not be plain http")
            XCTAssertFalse(link.title.isEmpty)
        }
        XCTAssertEqual(Set(SettingsStore.donationLinks.map(\.id)).count,
                       SettingsStore.donationLinks.count, "ids must be unique — they are ForEach's identity")
    }
}
