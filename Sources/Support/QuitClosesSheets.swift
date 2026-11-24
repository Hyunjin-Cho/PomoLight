import AppKit
import ObjectiveC

/// Quitting must work while the settings sheet is open.
///
/// 2026-11-22 (#14): with the settings sheet open, PomoLight could not be quit. "Remove PomoLight"
/// (its button lives in that sheet) moved the app to the Trash and left it running; ⌘Q, the Dock's
/// Quit, an AppleScript `quit` — and logging out — were ignored the same way. The in-app updater quits
/// through `NSApp.terminate` too, and its Install button is in the same sheet.
///
/// What was measured on throwaway copies (scratch builds, 2026-11-22):
/// - quit with the sheet open: ignored 3/3. Without it: quit in 0.1–0.4 s. Close the sheet, ask again: 0.1 s.
/// - a marker written from `applicationShouldTerminate` never appeared with the sheet open — AppKit
///   refuses before asking the delegate, so the delegate cannot fix this.
/// - `NSPrincipalClass` cannot either: the running app object is `SwiftUI.AppKitApplication` (logged
///   at launch), whatever Info.plist names.
/// - closing the sheet with `endSheet` inside `terminate` worked 4 times in 5. The fifth time the sheet
///   was back: SwiftUI's own "settings shown" state was still true and it presented the sheet again.
///   So the state is switched off first (`dismissSettings`), and quitting waits until the sheet is gone.
/// - the wait happens inside `terminate`, not after it: OnePercent 0.1.0 treats a `terminate` that
///   returns as "the app refused to quit" and reports an error, so a deferred quit is not an option.
///   2026-11-24 (#27): still so in 0.1.2 — its live `relaunch` opens the new copy, calls
///   `NSApp.terminate`, and throws `quitCancelled` if that returns.
///
/// Two hooks, installed at launch:
/// 1. `terminate(_:)` on the running app's own class — the menu's Quit (⌘Q), Remove PomoLight, the updater.
/// 2. the quit Apple Event (Dock, AppleScript, logout), which never reached `terminate` while a sheet
///    was up, is answered here: close the sheet, then `terminate`.
/// The settings hold nothing that needs saving, so closing the sheet loses nothing.
@MainActor
enum QuitClosesSheets {
    /// Switches the app's own "settings shown" state off. Set by `PomoLightApp`.
    static var dismissSettings: (() -> Void)?

    private static let quitEventHandler = QuitEventHandler()

    static func install() {
        hookTerminate()
        NSAppleEventManager.shared().setEventHandler(quitEventHandler,
                                                     andSelector: #selector(QuitEventHandler.handleQuit(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kCoreEventClass),
                                                     andEventID: AEEventID(kAEQuitApplication))
    }

    private static var sheetIsOpen: Bool { NSApp.windows.contains { $0.attachedSheet != nil } }

    /// Closes any open sheet and returns once it is gone (at most about 1.5 s).
    static func closeSheetsAndWait() {
        guard sheetIsOpen else { return }
        dismissSettings?()
        let deadline = Date().addingTimeInterval(1.5)
        while sheetIsOpen && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        // A sheet that is not ours (or a state that did not let go): close it the AppKit way.
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        // One more turn so SwiftUI finishes the dismissal it has just made.
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    /// Replaces `terminate(_:)` on the app object's actual class (an override is added there if the
    /// class only inherits it), keeping the original implementation and calling it after the sheets close.
    private static func hookTerminate() {
        guard let app = NSApp, let cls = object_getClass(app) else { return }
        let selector = #selector(NSApplication.terminate(_:))
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        typealias Terminate = @convention(c) (AnyObject, Selector, Any?) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Terminate.self)
        let replacement: @convention(block) (AnyObject, Any?) -> Void = { receiver, sender in
            MainActor.assumeIsolated { closeSheetsAndWait() }
            original(receiver, selector, sender)
        }
        class_replaceMethod(cls, selector, imp_implementationWithBlock(replacement), method_getTypeEncoding(method))
    }
}

/// Target for the quit Apple Event (`aevt/quit`).
private final class QuitEventHandler: NSObject {
    @MainActor @objc func handleQuit(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        QuitClosesSheets.closeSheetsAndWait()
        NSApp.terminate(nil)
    }
}
