import SwiftUI
import AppKit

/// Caps the main window so it can't balloon — a timer never needs to grow — while
/// still allowing it to shrink to stay compact. Blocks native full screen and the
/// green zoom (maximize) button; the max size is enforced by the content frame +
/// `.windowResizability(.contentSize)`. The window stays a tidy card.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            // Keep `.resizable` so the user can still drag it SMALLER; the content
            // max-frame prevents it from growing past the comfortable size.
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.insert(.fullScreenNone)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.standardWindowButton(.zoomButton)?.alphaValue = 0.35
            // Hard ceiling against window-tiling tools that call setFrame directly.
            window.maxSize = NSSize(width: 360, height: 520)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
