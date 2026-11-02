import SwiftUI

/// What the primary button says and shows in each phase. The main window's
/// `ControlsView` and the menu-bar popover's `MenuBarContent` both draw it.
///
/// 2026-11-02: the two views each carried an identical copy of these switches.
/// The title stays a `LocalizedStringKey` on purpose — handed a `String`, `Text`,
/// `.help` and `.accessibilityLabel` take it verbatim and skip the translations.
/// It lives here, not in TimerEngine.swift, because the engine does not import
/// SwiftUI and the host-less test target compiles that file on its own.
extension TimerEngine.Phase {
    var primaryActionTitle: LocalizedStringKey {
        switch self {
        case .idle:     return "Start"
        case .running:  return "Pause"
        case .paused:   return "Resume"
        case .finished: return "Dismiss"
        }
    }

    var primaryActionIcon: String {
        switch self {
        case .idle, .paused: return "play.fill"
        case .running:       return "pause.fill"
        case .finished:      return "checkmark"
        }
    }
}
