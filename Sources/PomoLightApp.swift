import SwiftUI

@main
struct PomoLightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .injectEnvironment(model)
                // Cap the max so it can't balloon, but allow shrinking to stay compact.
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 360,
                       minHeight: 430, idealHeight: 480, maxHeight: 480)
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
