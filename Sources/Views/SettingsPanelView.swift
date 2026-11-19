import SwiftUI
import AppKit

/// One calm in-window settings panel: theme color, alarm sound, and end-of-timer
/// behavior. Changes apply live — there is no Save step.
struct SettingsPanelView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(SettingsStore.self) private var settings
    @Environment(AppModel.self) private var app
    let palette: Palette
    @Binding var isPresented: Bool
    var scrolls: Bool = true

    var body: some View {
        Group {
            if scrolls {
                ScrollView { contentStack }
            } else {
                contentStack
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 540)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))   // keep content inside the card
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .onExitCommand { isPresented = false }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            themeSection
            soundSection
            endSection
            removeSection
            footer
        }
        .padding(20)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.primaryText)
            Spacer()
            Button("Done") { isPresented = false }
                .buttonStyle(.plain)
                .font(.system(size: 16, weight: .semibold, design: .rounded))   // same size as the title
                .foregroundStyle(palette.primaryText)   // fixed ink, like the title — not theme-tinted
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("THEME COLOR")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                      spacing: 12) {
                ForEach(theme.presets) { preset in
                    swatch(color: preset.swatch,
                           selected: theme.current.id == preset.id,
                           label: preset.name) {
                        theme.selectPreset(id: preset.id)
                    }
                }
            }
        }
    }

    private func swatch(color: Color, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(selectionRing(selected))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func selectionRing(_ selected: Bool) -> some View {
        Circle()
            .strokeBorder(palette.surface, lineWidth: selected ? 2 : 0)
            .overlay(
                Circle().strokeBorder(selected ? palette.primaryText.opacity(0.7) : .clear,
                                      lineWidth: selected ? 1.5 : 0)
                    .padding(-2)
            )
    }

    // MARK: Sound

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("ALARM SOUND")
            ForEach(AlarmSound.allCases) { sound in
                let isSelected = settings.alarmSound == sound
                HStack(spacing: 10) {
                    // The whole left area is a real, VoiceOver/keyboard-operable
                    // button that selects (and auditions) the sound.
                    Button {
                        settings.alarmSound = sound
                        app.preview(sound)
                    } label: {
                        HStack(spacing: 10) {
                            // 2026-08-21: the selected dot used to be drawn with
                            // `palette.accent`, a FILL role. Measured 1.20:1 (Lime) …
                            // 2.94:1 (Indigo) against the panel's `surface`, where an
                            // icon needs 3:1 — so the SELECTED row was fainter than
                            // the three unselected ones and all four read as "off".
                            // `controlIcon` is the role that clears 3:1 vs bg AND
                            // surface, and ContrastTests pins that for all 15 themes.
                            // Selection is still carried by the glyph, not by colour.
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(palette.controlIcon)
                            Text(verbatim: sound.displayName)   // sound names stay English
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(palette.primaryText)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sound.displayName)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])

                    CircleIconButton(systemName: "play.fill", tint: palette.secondaryText,
                                     soft: palette.accentSoft, size: 28,
                                     font: .system(size: 11)) {
                        app.preview(sound)
                    }
                    .accessibilityLabel(Text("Preview \(sound.displayName)"))
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(palette.secondaryText).font(.system(size: 11))
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { settings.alarmVolume }, set: { settings.alarmVolume = $0 }), in: 0...1)
                    // 2026-08-21: same FILL-as-state-indicator mistake as the radio
                    // above — the filled part of the track was invisible against
                    // `surface`, so the volume was unreadable at a glance.
                    .tint(palette.controlIcon)
                    .accessibilityLabel("Alarm volume")
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(palette.secondaryText).font(.system(size: 11))
                    .accessibilityHidden(true)
            }
            sectionNote("The end is also shown visually, so a muted Mac still alerts you.")
        }
    }

    // MARK: End behavior

    private var endSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("WHEN THE TIMER ENDS")
            toggle("Repeat sound until dismissed", \.repeatUntilDismissed)
            sectionNote("Otherwise the alarm rings 3 times.")
                .padding(.top, -4)
            toggle("Show notification", \.notificationsEnabled)
            sectionTitle("GENERAL").padding(.top, 6)
            toggle("Show seconds in custom entry", \.showSeconds)
            toggle("Show timer in menu bar", \.showInMenuBar)
            toggle("Keep Mac awake while running", \.keepAwake)
        }
    }

    /// An explicit Binding straight off the @Observable store — avoids any
    /// @Bindable scoping subtleties so toggles reliably persist & apply.
    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func toggle(_ label: LocalizedStringKey, _ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) -> some View {
        Toggle(isOn: boolBinding(keyPath)) {
            Text(label)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(palette.primaryText)
                .fixedSize(horizontal: false, vertical: true)   // wrap long translations
                .multilineTextAlignment(.leading)
        }
        .toggleStyle(.switch)
        // 2026-08-21: an "on" switch filled with the raw accent sat at 1.20–2.94:1
        // against `surface` — the on/off states were barely distinguishable.
        .tint(palette.controlIcon)
    }

    // MARK: Remove (#52)

    /// Deliberately quiet. A destructive control does not need to catch the eye in
    /// a list of preferences — the confirmation is where the weight belongs, and a
    /// red row here would pull attention every time someone came to change a theme.
    private var removeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().opacity(0.3)
            Button("Remove PomoLight…") { confirmRemoval() }
                .buttonStyle(.plain)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 4)
            sectionNote("Moves PomoLight to the Trash and deletes what it saved.")
        }
    }

    private func confirmRemoval() {
        let traces = Uninstaller.existingTraces()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Remove PomoLight?")
        // Say what will happen in the concrete, including the part no software can
        // do for them. A confirmation that only says "are you sure" teaches people
        // to click through confirmations.
        var lines = [
            String(localized: "PomoLight will be moved to the Trash, so you can put it back from there if you change your mind."),
            String(localized: "Your themes, sounds and durations will be deleted."),
        ]
        if traces.count > 1 {
            lines.append(String(format: String(localized: "%d files it saved will be removed."), traces.count))
        }
        lines.append(String(localized: "Its entry in System Settings ▸ Notifications belongs to macOS and stays until macOS drops it."))
        alert.informativeText = lines.joined(separator: "\n\n")

        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons[0].hasDestructiveAction = true
        // Cancel takes Return. Uninstalling must not be one stray keypress away.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try Uninstaller.performUninstall(settings: settings)
            NSApp.terminate(nil)
        } catch {
            let failed = NSAlert()
            failed.alertStyle = .critical
            failed.messageText = String(localized: "PomoLight could not be moved to the Trash")
            // Nothing was deleted — say so, or the next thing they do is go looking
            // for the settings they think they just lost.
            failed.informativeText = error.localizedDescription + "\n\n"
                + String(localized: "Nothing was removed. You can move it yourself:")
                + "\n" + Bundle.main.bundleURL.path
            failed.addButton(withTitle: String(localized: "Show in Finder"))
            failed.addButton(withTitle: String(localized: "OK"))
            if failed.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.3)
            HStack {
                // 2026-11-19 (#6): was the donation heart + "Support PomoLight". The
                // address itself is the label — it says where the click goes and needs no
                // translation. Measured with the AX API: an AXLink whose description is
                // the address and whose AXURL is the profile, with no extra label needed.
                // (System Events' `description` shows only "링크" here — it cannot see
                // SwiftUI's labels on macOS 27, even the gear's; don't trust it for this.)
                Link(destination: SettingsStore.developerPage) {
                    HStack(spacing: 3) {
                        Text(verbatim: developerPageLabel)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 13, design: .rounded))
                    // secondaryText, like the version beside it — NOT the link blue or
                    // the accent: accent is a FILL and vanishes as ink (Theme.swift).
                    .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: SettingsStore.developerPage.absoluteString))
                Spacer()
                Text(verbatim: "v\(appVersion)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
            }
        }
    }

    /// "github.com/Hyunjin-Cho" — the address without its scheme, built from the one
    /// URL so the label and the link cannot drift apart.
    private var developerPageLabel: String {
        let url = SettingsStore.developerPage
        return (url.host() ?? "") + url.path()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2026.01"
    }

    private func sectionTitle(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(palette.secondaryText)
    }

    /// The small explanatory line under a control.
    private func sectionNote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
