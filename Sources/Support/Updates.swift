import Foundation
import OnePercent

/// In-app updates (#73), through OnePercent — the owner's own updater, the
/// HaneulKeyboard one generalised into a package (github.com/Hyunjin-Cho/OnePercent, MIT).
///
/// 2026-11-20 owner decisions, kept here because the code is where they show:
/// · **Quiet.** A check once a month; a found version is never a window popping up over
///   a focus session. It shows only as a line in the menu-bar popover and in Settings.
///   So there is deliberately no `onUpdateAvailable` handler.
/// · **Installing is always a button press**, and refused while a timer is running,
///   paused or ringing — replacing the app reopens it, which would end the session.
/// · Releases are GitHub releases of this repository, tag = version (`1.1`), asset
///   `PomoLight_<tag>.zip` made with `ditto -c -k --keepParent`, signed with Developer ID
///   and notarized. Every release must raise CFBundleVersion as well (project.yml).
/// · The administrator-password path stays off (OnePercent's default) until it has been
///   tried on a real Mac.
@MainActor
enum PomoLightUpdates {
    static let configuration: OnePercentConfiguration = {
        var configuration = OnePercentConfiguration(
            repository: "Hyunjin-Cho/PomoLight",
            teamIdentifier: "6RH6FXY82P",
            bundleIdentifier: "com.vismo.pomolight",
            appName: "PomoLight",
            schedule: .monthly,
            defaultsKeyPrefix: "pl.update.",
            // PomoLight is a few megabytes; OnePercent's defaults are sized for apps a
            // hundred times bigger. Tighter limits stop a bad download sooner.
            limits: Limits(maxAssetBytes: 100 * 1024 * 1024, maxMetadataBytes: 2 * 1024 * 1024,
                           archive: ArchiveLimits(entries: 5_000, bytes: 300 * 1024 * 1024, seconds: 120)))
        #if DEBUG
        // Real-device testing against a scratch repository (docs: OnePercent's MANUAL-TEST.md).
        // Debug builds only, and only when the variable is set.
        if let test = ProcessInfo.processInfo.environment["POMO_UPDATE_TEST_REPO"], !test.isEmpty {
            configuration.testRepository = test
        }
        #endif
        return configuration
    }()

    /// The one updater. Shared rather than owned by `AppModel` so the host-less test
    /// bundle, which compiles `AppModel.swift` directly, does not need the package.
    static let shared = OnePercentUpdater(configuration: configuration)

    /// Called once at launch: record the version, clear leftovers of an interrupted
    /// update, refuse installs during a session, and start the monthly check.
    static func start(model: AppModel) {
        #if DEBUG
        // The snapshot renderer and the uninstall self-test are real launches that must
        // leave no trace (see Snapshot.swift): no network, nothing written to the
        // owner's preferences.
        let environment = ProcessInfo.processInfo.environment
        if environment["POMO_SNAPSHOT"] != nil || environment["POMO_UNINSTALL_SELFTEST"] != nil { return }
        #endif
        let updater = shared
        updater.noteLaunch()
        updater.installGuard = { [weak model] in
            guard let model, model.engine.phase != .idle else { return nil }
            return String(localized: "Stop the timer first to install the update.")
        }
        #if DEBUG
        // 2026-11-20: development builds get launched over and over (by hand and by the
        // verification scripts); they only check by themselves when pointed at a test
        // repository. "Check Now" in Settings still works.
        guard configuration.testRepository != nil else { return }
        #endif
        updater.startAutomaticChecks()
    }

    /// True while an update is being downloaded, checked or put in place — the
    /// uninstaller must not run then.
    static var isInstalling: Bool {
        switch shared.phase {
        case .downloading, .verifying, .installing: return true
        default: return false
        }
    }
}
