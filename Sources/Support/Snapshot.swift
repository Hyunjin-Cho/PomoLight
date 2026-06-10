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
        Spec(name: "01_default_idle_peach_light", themeID: "peach", scheme: .light, phase: .idle),
        Spec(name: "02_running_sage_light", themeID: "sage", scheme: .light, phase: .running),
        Spec(name: "03_running_lavender_dark", themeID: "lavender", scheme: .dark, phase: .running),
        Spec(name: "04_finished_rose_light", themeID: "rose", scheme: .light, phase: .finished),
        Spec(name: "05_settings_glacier_light", themeID: "glacier", scheme: .light, phase: .settings),
        Spec(name: "06_idle_butter_dark", themeID: "butter", scheme: .dark, phase: .idle),
    ]

    static func render(into dir: String) {
        for spec in specs {
            let model = AppModel()
            model.theme.selectPreset(id: spec.themeID)
            configure(model: model, for: spec.phase)
            let path = (dir as NSString).appendingPathComponent("\(spec.name).png")
            renderView(content(for: spec, model: model), to: path)
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
    private static func content(for spec: Spec, model: AppModel) -> some View {
        Group {
            if spec.phase == .settings {
                ZStack {
                    RootView()
                    Color.black.opacity(0.28)
                    SettingsPanelView(palette: model.theme.palette(for: spec.scheme),
                                      isPresented: .constant(true), scrolls: false)
                }
            } else {
                RootView()
            }
        }
        .injectEnvironment(model)
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
