#if DEBUG
import AppKit

/// Drives "quit while the settings sheet is open" for `Scripts/quit_check.sh`.
///
/// 2026-11-22 (#17): #14 — with the sheet open, macOS refused to quit, so Settings ▸
/// Remove PomoLight… left the app running — passed all seven verify stages and shipped
/// in a notarized build. No check ever launched the app with the sheet up. The fix
/// (`QuitClosesSheets`) hooks `terminate(_:)` on a SwiftUI-private class and replaces
/// the quit Apple Event handler, either of which a macOS update could undo silently,
/// so it needs a check that runs on every build.
///
/// `POMO_QUIT_SELFTEST=terminate` opens the sheet, then calls `NSApp.terminate` itself:
/// the path the Quit menu item (⌘Q), Remove PomoLight… and an update install take.
/// `POMO_QUIT_SELFTEST=wait` opens the sheet and waits for a quit Apple Event from
/// outside: the path Dock ▸ Quit, logging out and AppleScript take.
/// Either way it says on stderr once the sheet is really attached, so a pass cannot
/// come from a sheet that never opened.
@MainActor
enum QuitSelfTest {
    /// Set by `PomoLightApp`, which owns the model.
    static var openSettings: (() -> Void)?

    static func runIfRequested() {
        guard let mode = ProcessInfo.processInfo.environment["POMO_QUIT_SELFTEST"] else { return }
        openSettings?()
        Task { @MainActor in
            for _ in 0..<50 {   // 5 s for the sheet to appear
                // The window's frame would be saved as `NSWindow Frame main` in the owner's
                // real preferences (measured on the first run of this check), and its state
                // under Saved Application State. Neither has anything to do with quitting.
                for window in NSApp.windows {
                    window.setFrameAutosaveName("")
                    window.isRestorable = false
                }
                if NSApp.windows.contains(where: { $0.attachedSheet != nil }) {
                    report("QUITSELFTEST sheet open")
                    if mode == "terminate" { NSApp.terminate(nil) }
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            report("QUITSELFTEST the settings sheet never opened")
            exit(4)
        }
    }

    private static func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
#endif
