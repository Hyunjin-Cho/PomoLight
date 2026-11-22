import SwiftUI
import OnePercent

enum WindowID {
    static let main = "main"
}

@main
struct PomoLightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        let model = AppModel()
        #if DEBUG
        // 2026-11-22 (#16): the check launches (see CheckLaunch) build this same app, its own
        // model and menu-bar scene included, and SwiftUI writes `pl.showInMenuBar` through the
        // menu-bar binding — into the owner's real preferences (measured: one
        // silent_launch_check run added it to an empty domain). cfprefsd puts that on disk
        // seconds later, so it also failed the NEXT check's "real install untouched" test.
        // Those runs work on throwaway suites of their own; the real model only reads.
        if CheckLaunch.isActive { model.settings.stopPersisting() }
        // 2026-11-22 (#17): quit_check.sh opens the settings sheet through the same state.
        QuitSelfTest.openSettings = { model.showSettings = true }
        #endif
        _model = State(initialValue: model)
        // 2026-11-20 (#73): updates start with the app, not with the window — the window
        // can be closed while the app stays in the menu bar.
        PomoLightUpdates.start(model: model)
        // 2026-11-22 (#14): quitting closes the settings sheet first, through the app's own state.
        QuitClosesSheets.dismissSettings = { model.showSettings = false }
    }

    var body: some Scene {
        // A single, reopenable window (so "Open PomoLight" from the menu bar can
        // bring it back after it's been closed).
        Window("PomoLight", id: WindowID.main) {
            RootView()
                .injectEnvironment(model)
                // Compact by default; can shrink, and can grow up to +50% — no further.
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 540,
                       minHeight: 430, idealHeight: 480, maxHeight: 720)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 480)
        .commands {
            CommandGroup(replacing: .newItem) {}            // no "New Window"
            CommandGroup(replacing: .appInfo) {
                Button("About PomoLight") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
        }

        MenuBarExtra(isInserted: menuBarBinding) {
            MenuBarContent()
                .injectEnvironment(model)
        } label: {
            MenuBarLabel()
                .environment(model.engine)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarBinding: Binding<Bool> {
        Binding(get: { model.settings.showInMenuBar },
                set: { model.settings.showInMenuBar = $0 })
    }
}

extension View {
    /// Injects the shared object graph into the environment in one call.
    func injectEnvironment(_ model: AppModel) -> some View {
        self
            .environment(model)
            .environment(model.engine)
            .environment(model.theme)
            .environment(model.settings)
            .environment(PomoLightUpdates.shared)
    }
}
