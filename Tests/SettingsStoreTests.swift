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
        XCTAssertEqual(s.alarmSound, .marimba)
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
    ///
    /// 2026-11-17 (#61): this includes the three voices that were removed —
    /// `synthBell` (Soft Chime, the old default), `bell` and `pulse`. Anyone who had
    /// one of them chosen hears the new default instead of nothing.
    func testAnUnknownStoredAlarmSoundFallsBackToTheDefaultVoice() {
        for stored in ["theremin", "synthBell", "bell", "pulse"] {
            defaults.set(stored, forKey: "pl.alarmSound")
            XCTAssertEqual(SettingsStore(defaults: defaults).alarmSound, .marimba,
                           "a stored \"\(stored)\" did not land on the default voice")
        }
    }

    /// And the one old value that still exists keeps meaning what it meant: Marimba
    /// was a voice before #61's replacement and is one after it, under the same
    /// rawValue — so a saved Marimba is not quietly reset.
    func testAStoredMarimbaFromBeforeTheNewVoicesIsStillMarimba() {
        defaults.set("marimba", forKey: "pl.alarmSound")
        XCTAssertEqual(SettingsStore(defaults: defaults).alarmSound, .marimba)
    }

    /// Every `AlarmSound` must round-trip through its rawValue — renaming a case
    /// would otherwise reset everyone's choice on the next launch without a sound.
    func testEveryAlarmSoundRoundTripsThroughItsStoredRawValue() {
        for sound in AlarmSound.allCases {
            let writer = SettingsStore(defaults: defaults)
            writer.alarmSound = sound
            XCTAssertEqual(SettingsStore(defaults: defaults).alarmSound, sound,
                           "\(sound.rawValue) did not survive a round trip")
        }
    }

    /// The uninstaller deletes the preferences file, and anything written after
    /// that recreates it. Measured 2026-08-21: the file came back holding a single
    /// `pl.showInMenuBar`, written when SwiftUI removed the menu-bar scene during
    /// termination — half a second after the domain had been removed. So the store
    /// has an off switch, and this is the test that it is really off.
    func testStopPersistingKeepsLaterChangesOutOfUserDefaults() {
        let s = SettingsStore(defaults: defaults)
        s.selectedThemeID = "violet"
        XCTAssertEqual(defaults.string(forKey: "pl.selectedThemeID"), "violet")

        s.stopPersisting()
        s.selectedThemeID = "mint"
        s.alarmVolume = 0.11
        s.showInMenuBar = false
        s.repeatUntilDismissed = true

        XCTAssertEqual(defaults.string(forKey: "pl.selectedThemeID"), "violet",
                       "a suspended store must not write")
        XCTAssertEqual(s.selectedThemeID, "mint",
                       "…but the value in memory still changes, so the UI keeps working")
    }

    /// The sequence the uninstaller actually performs: stop writing, then wipe the
    /// domain. Nothing may repopulate it afterwards.
    func testNothingRepopulatesTheDomainAfterItIsWipedWithPersistenceOff() {
        let s = SettingsStore(defaults: defaults)
        s.selectedThemeID = "violet"
        s.stopPersisting()
        defaults.removePersistentDomain(forName: suiteName)

        s.showInMenuBar = false          // the write that used to resurrect the file
        s.lastDurationMinutes = 42

        // Ask what is actually STORED, not what `string(forKey:)` would answer.
        // `removePersistentDomain` clears the stored values but leaves the ones
        // `register(defaults:)` supplies, so the ordinary getters keep returning
        // "coral" and 30 — reading them here would have made this test pass while
        // proving nothing. The persistent domain is the thing that becomes a file.
        let stored = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertTrue(stored.isEmpty,
                      "a suspended store wrote \(stored.count) key(s) after the domain was " +
                      "wiped — on disk that is the preferences file coming back: \(stored)")
    }

    /// 2026-11-19 (#6): replaced the donation-link test when donations were dropped.
    /// Pins the one link Settings still shows to the owner's public profile over
    /// https. The footer draws `host + path` as its label, so a change here changes
    /// what people read as well as where the click goes — both are worth a red test.
    /// The repository itself is private, which is why this must stay a PROFILE path
    /// (one component) and not grow a `/PomoLight` on the end.
    func testTheDeveloperLinkIsTheOwnersPublicGitHubProfile() {
        let url = SettingsStore.developerPage
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host(), "github.com")
        XCTAssertEqual(url.path(), "/Hyunjin-Cho",
                       "a profile, not a repository — the PomoLight repository is private")
    }
}
