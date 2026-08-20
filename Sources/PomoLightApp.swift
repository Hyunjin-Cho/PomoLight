import SwiftUI

enum WindowID {
    static let main = "main"
}

@main
struct PomoLightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

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
    }
}
