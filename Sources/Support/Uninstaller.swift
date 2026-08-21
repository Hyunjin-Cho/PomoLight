import AppKit

/// Removing PomoLight from inside PomoLight (#52).
///
/// `Scripts/uninstall.sh` can only help someone who has the repository. Anyone who
/// downloaded a .dmg had no route at all except "drag it to the Trash and then go
/// find its preferences yourself", which is homework, not a route. This is the
/// same job, reachable from the settings panel, at any time.
///
/// Two decisions worth stating, because both could reasonably have gone the other
/// way:
///
/// · **The app is moved to the Trash, never deleted outright.** Uninstalling is
///   the one action a user cannot undo by relaunching, so it should be undoable by
///   the ordinary means. It is also what macOS trains people to expect.
/// · **The app bundle goes first, settings second.** Moving to the Trash is the
///   step that can fail — no permission, a read-only volume, a copy running from a
///   disk image. If that fails we stop with everything intact. The reverse order
///   would wipe someone's themes and durations and then tell them the app is still
///   installed.
@MainActor
enum Uninstaller {

    /// Everything a PomoLight install has ever written under `~/Library`, current
    /// and historical.
    ///
    /// 🔒 This list is mirrored in `Scripts/uninstall.sh`, and
    /// `UninstallerTests.testTheShellScriptRemovesExactlyTheSamePaths` fails if the
    /// two drift apart. Two copies of a path list is exactly the shape of problem
    /// this repo has been bitten by before (the contrast audit kept its own copy of
    /// the palette maths and it silently disagreed with the app), so the mirror is
    /// machine-checked rather than promised in a comment.
    static func tracePaths(home: URL) -> [URL] {
        let library = home.appendingPathComponent("Library")
        func p(_ path: String) -> URL { library.appendingPathComponent(path) }
        return [
            // Written by the app that ships today — settings and window positions.
            p("Preferences/com.vismo.pomolight.plist"),
            // Left by the widget, removed in PR #33.
            p("Preferences/group.com.vismo.pomolight.plist"),
            p("Containers/com.vismo.pomolight.widget"),
            p("Group Containers/group.com.vismo.pomolight"),
            p("Application Scripts/com.vismo.pomolight.widget"),
            p("Application Scripts/group.com.vismo.pomolight"),
            // Left by the sandbox change that was reverted in PR #25.
            p("Application Scripts/com.vismo.pomolight"),
            // Written by macOS on our behalf.
            p("Saved Application State/com.vismo.pomolight.savedState"),
            p("Caches/com.vismo.pomolight"),
            p("HTTPStorages/com.vismo.pomolight"),
        ]
    }

    /// What a confirmation dialog should be able to say without guessing.
    static func existingTraces(home: URL = URL(fileURLWithPath: NSHomeDirectory())) -> [URL] {
        tracePaths(home: home).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    enum Failure: LocalizedError {
        case couldNotTrash(String)

        var errorDescription: String? {
            switch self {
            case .couldNotTrash(let reason):
                return reason
            }
        }
    }

    /// Move the app to the Trash, then arrange for its files to go once this
    /// process is gone. Throws — with nothing changed — if the move fails.
    ///
    /// Everything it acts on is a parameter with the real thing as its default, so
    /// `runSelfTestIfRequested()` below can drive the identical code path against a
    /// throwaway bundle and a throwaway preferences suite. Uninstalling is the one
    /// feature that cannot be tried out by hand without consequences, so it needed
    /// to be reachable by a check that runs on every build instead.
    static func performUninstall(settings: SettingsStore,
                                 defaults: UserDefaults = .standard,
                                 domainName: String? = nil,
                                 paths: [URL]? = nil,
                                 bundleURL: URL = Bundle.main.bundleURL) throws {
        let domainName = domainName ?? bundleIdentifier
        let paths = paths ?? tracePaths(home: URL(fileURLWithPath: NSHomeDirectory()))

        // 1. The step that can fail, first.
        do {
            try FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
        } catch {
            throw Failure.couldNotTrash(error.localizedDescription)
        }

        // 2. Silence everything that could still write a preference. This is the
        //    belt, not the braces: `Scripts/uninstall_check.sh` still passes with
        //    this line removed, because step 3's ordering catches the write anyway.
        //    It stays because removing the cause is better than relying on the
        //    cleanup to mop it up, and because it costs one line. Do not read it as
        //    the thing that fixed the bug — that was the ordering below.
        settings.stopPersisting()
        for window in NSApp.windows {
            window.setFrameAutosaveName("")     // no `NSWindow Frame …` on the way out
            window.isRestorable = false
        }
        defaults.removePersistentDomain(forName: domainName)

        // 3. Preferences are served from a cache that outlives us, so deleting the
        //    file from in here is not enough on its own — cfprefsd can write it
        //    back from memory. Hand the last step to something that runs AFTER this
        //    process exits.
        scheduleCleanupAfterExit(paths: paths)
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.vismo.pomolight"
    }

    /// A detached `/bin/sh` that waits for us to disappear, removes what is left,
    /// and flushes the preferences cache. It is deliberately tiny and quoted-safe:
    /// every path comes from `tracePaths`, none of it from user input.
    private static func scheduleCleanupAfterExit(paths: [URL]) {
        let quoted = paths
            .map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let pid = ProcessInfo.processInfo.processIdentifier
        // `kill -0` asks "does this process still exist" without signalling it.
        // 🚨 This ordering IS the fix, and it is the opposite of the obvious one.
        // cfprefsd caches preference domains in memory and flushes them as it
        // exits, so `rm` then `killall` writes the file straight back — measured,
        // twice: once for real (the file returned holding a single
        // `pl.showInMenuBar` that SwiftUI wrote while tearing the menu-bar scene
        // down) and once deliberately, by putting the old order back and watching
        // `Scripts/uninstall_check.sh` fail. Stop the cache first, delete second.
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        sleep 0.5
        killall cfprefsd 2>/dev/null
        sleep 0.5
        rm -rf \(quoted)
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        try? task.run()   // best effort: if it cannot start, the app is still gone
    }
}


#if DEBUG
extension Uninstaller {
    /// Runs the real uninstall against a throwaway app and a throwaway preferences
    /// suite, then quits. Driven by `Scripts/uninstall_check.sh`; see that file for
    /// why it exists.
    ///
    /// The point is that this is not a rehearsal — the same `performUninstall` runs,
    /// with the same ordering and the same detached cleanup. Only the targets are
    /// substituted, which is why they are parameters.
    static func runSelfTestIfRequested() {
        guard let suite = ProcessInfo.processInfo.environment["POMO_UNINSTALL_SELFTEST"],
              !suite.isEmpty else { return }
        guard let defaults = UserDefaults(suiteName: suite) else {
            FileHandle.standardError.write("SELFTEST could not open suite \(suite)\n".data(using: .utf8)!)
            exit(2)
        }

        // Give it something to lose, then make sure the file is really on disk.
        let settings = SettingsStore(defaults: defaults)
        settings.selectedThemeID = "violet"
        settings.showInMenuBar = true
        defaults.synchronize()

        let plist = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(suite).plist")

        do {
            try performUninstall(settings: settings,
                                 defaults: defaults,
                                 domainName: suite,
                                 paths: [plist],
                                 bundleURL: Bundle.main.bundleURL)
        } catch {
            FileHandle.standardError.write("SELFTEST uninstall threw: \(error)\n".data(using: .utf8)!)
            exit(3)
        }

        // The write that used to bring the file back, half a second after the
        // domain was wiped. Doing it deliberately here means the check proves the
        // fix rather than merely failing to reproduce the bug.
        settings.showInMenuBar = false
        settings.selectedThemeID = "mint"

        FileHandle.standardError.write("SELFTEST performed\n".data(using: .utf8)!)
        exit(0)
    }
}
#endif
