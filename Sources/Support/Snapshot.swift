import SwiftUI
import AppKit
import ImageIO

#if DEBUG
/// Offscreen UI snapshots via `ImageRenderer` (needs no Screen Recording
/// permission). Triggered by launching with the env var `POMO_SNAPSHOT=<dir>`;
/// renders a few real screens to PNGs and quits. Used for build verification.
@MainActor
enum Snapshot {
    static func runIfRequested() {
        guard let dir = ProcessInfo.processInfo.environment["POMO_SNAPSHOT"] else { return }
        let base = dir.isEmpty ? NSTemporaryDirectory() : dir
        render(into: base)
        NSApp.terminate(nil)
    }

    struct Spec { let name: String; let themeID: String; let scheme: ColorScheme; let phase: RenderPhase }
    enum RenderPhase { case idle, running, finished, settings }

    private static let specs: [Spec] = [
        Spec(name: "01_idle_sky_light", themeID: "sky", scheme: .light, phase: .idle),
        Spec(name: "02_running_lime_light", themeID: "lime", scheme: .light, phase: .running),
        Spec(name: "03_running_violet_dark", themeID: "violet", scheme: .dark, phase: .running),
        Spec(name: "04_finished_rose_light", themeID: "rose", scheme: .light, phase: .finished),
        Spec(name: "05_settings_mint_light", themeID: "mint", scheme: .light, phase: .settings),
        Spec(name: "06_idle_yellow_light", themeID: "yellow", scheme: .light, phase: .idle),
    ]

    /// 2026-08-15: taking snapshots used to CHANGE the user's own settings.
    /// `AppModel().theme.selectPreset(id:)` writes `pl.selectedThemeID` straight
    /// through to `UserDefaults.standard`, so a run left the app stuck on the last
    /// spec's theme ("yellow"), and `AppModel.init` republished the App Group
    /// snapshot once per spec. Both are now contained:
    ///  - the views are driven by a throwaway defaults suite, thrown away after,
    ///  - the App Group snapshot is captured up front and put back at the end.
    /// A pleasant side effect: every spec now renders from registered defaults, so
    /// snapshots look the same on any machine instead of mirroring whoever ran them.
    static func render(into dir: String) {
        let suiteName = "pl.snapshot.\(UUID().uuidString)"
        guard let scratchDefaults = UserDefaults(suiteName: suiteName) else {
            FileHandle.standardError.write(
                "PomoLight snapshots skipped — could not open a scratch defaults suite\n".data(using: .utf8)!)
            return
        }
        defer { scratchDefaults.removePersistentDomain(forName: suiteName) }

        // 2026-08-21: this used to snapshot and restore the App Group state around
        // the render, because building AppModels here published fake timer states to
        // the widget. Nothing leaves the process any more, so there is nothing to
        // put back.

        for spec in specs {
            let model = AppModel()
            let settings = SettingsStore(defaults: scratchDefaults)
            let theme = ThemeStore(settings: settings)
            theme.selectPreset(id: spec.themeID)       // writes to the scratch suite only
            configure(model: model, for: spec.phase)
            let path = (dir as NSString).appendingPathComponent("\(spec.name).png")
            renderView(content(for: spec, model: model, settings: settings, theme: theme), to: path)
        }
        FileHandle.standardError.write("PomoLight snapshots written to \(dir)\n".data(using: .utf8)!)
    }

    private static func configure(model: AppModel, for phase: RenderPhase) {
        switch phase {
        case .idle, .settings:
            model.engine.setMinutes(25)
        case .running:
            model.engine.setMinutes(25)
            model.engine.start()           // deadline-based; shows ~24:59 ticking
        case .finished:
            model.engine.setMinutes(25)
            model.engine.start()
            // Force the finished look without waiting 25 minutes.
            model.engine.debugForceFinish()
        }
    }

    @ViewBuilder
    private static func content(for spec: Spec, model: AppModel,
                                settings: SettingsStore, theme: ThemeStore) -> some View {
        Group {
            if spec.phase == .settings {
                ZStack {
                    RootView()
                    Color.black.opacity(0.28)
                    SettingsPanelView(palette: theme.palette(for: spec.scheme),
                                      isPresented: .constant(true), scrolls: false)
                }
            } else {
                RootView()
            }
        }
        // Deliberately NOT `.injectEnvironment(model)`: the theme and settings the
        // views read have to be the scratch pair above, not the ones `AppModel`
        // built from the user's real defaults. Everything else matches it.
        // (2026-08-15)
        .environment(model)
        .environment(model.engine)
        .environment(theme)
        .environment(settings)
        .environment(\.colorScheme, spec.scheme)
        .frame(width: spec.phase == .settings ? 380 : 360,
               height: spec.phase == .settings ? 760 : 480)
    }

    private static func renderView<V: View>(_ view: V, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }
}
#endif
