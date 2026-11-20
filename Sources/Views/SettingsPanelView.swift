import SwiftUI
import AppKit

/// The settings sheet: everything on one page, nothing to scroll. The left column is
/// what you see and hear (theme, alarm sound, volume); the right is what happens
/// (when the timer ends, general, removing the app). Changes apply live — there is no
/// Save step.
///
/// 2026-11-20 (#72, 오너 결정 시안 B): 메인 창(320 폭) 안에 겹쳐 그리던 카드를 창 밖으로 나오는 시트(580 폭, 두 단)로 바꿨다.
/// 겹쳐 그리던 카드는 창에 꽉 끼어 카드처럼 안 보였고 4화면을 스크롤해야 했다(시안 README 1절의 문제 12개).
/// 함께 고친 것: 스위치를 오른쪽 기둥에 정렬, 줄을 묶음 상자에, "완료"를 진짜 버튼으로, ▶ 바탕 원 상시 표시,
/// 테마 색 한 줄, 섹션 간격 16pt 고정, 꺼진 스위치 트랙을 한 단계 진하게. 시안: `~/Documents/Code-Reviews/20261120/pomolight/settings-redesign/proposals/B_sheet.md`.
struct SettingsPanelView: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(SettingsStore.self) private var settings
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let palette: Palette
    @Binding var isPresented: Bool

    /// Sheet width 580 = 20 + 262 + 16 + 262 + 20.
    static let width: CGFloat = 580
    private static let columnWidth: CGFloat = 262
    private static let sectionSpacing: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacing) {
            header
            // Reading order follows the layout: the left column top to bottom, then the right.
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                    themeSection
                    soundSection
                }
                .frame(width: Self.columnWidth, alignment: .leading)
                VStack(alignment: .leading, spacing: Self.sectionSpacing) {
                    endSection
                    generalSection
                    removeSection
                }
                .frame(width: Self.columnWidth, alignment: .leading)
            }
            footer
        }
        .padding(20)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette.bg)
        .onExitCommand { isPresented = false }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // 2026-11-20 (#72): 예전엔 제목과 같은 크기·굵기·색이라 두 번째 제목처럼 읽혔다. 이제 진짜 버튼(알약).
            Button("Done") { isPresented = false }
                .buttonStyle(PillButtonStyle(fill: palette.buttonFill, label: palette.buttonLabel))
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Theme

    private var themeSection: some View {
        section("THEME COLOR") {
            // 2026-11-20 (#72): 8개를 한 줄에(4×2 는 세로 공간만 썼다).
            HStack(spacing: 0) {
                ForEach(theme.presets) { preset in
                    swatch(color: preset.swatch,
                           selected: theme.current.id == preset.id,
                           label: preset.name) {
                        theme.selectPreset(id: preset.id)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
    }

    private func swatch(color: Color, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(selectionRing(selected))
                .padding(4)
                .contentShape(Circle())
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
                    .padding(-3)
            )
    }

    // MARK: Sound

    private var soundSection: some View {
        section("ALARM SOUND") {
            ForEach(Array(AlarmSound.allCases.enumerated()), id: \.element) { index, sound in
                if index > 0 { rowDivider }
                soundRow(sound)
            }
            rowDivider
            volumeRow
        }
    }

    private func soundRow(_ sound: AlarmSound) -> some View {
        let isSelected = settings.alarmSound == sound
        return HStack(spacing: 10) {
            // The whole left area is a real, VoiceOver/keyboard-operable button that
            // selects (and auditions) the sound.
            Button {
                settings.alarmSound = sound
                app.preview(sound)
            } label: {
                HStack(spacing: 10) {
                    // 2026-08-21: the selected dot used to be drawn with `palette.accent`,
                    // a FILL role — the selected row read fainter than the others.
                    // `controlIcon` clears 3:1 vs bg AND surface (ContrastTests pins it).
                    // Selection is still carried by the glyph, not by colour.
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(palette.controlIcon)
                    Text(verbatim: sound.displayName)   // sound names stay English
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(palette.primaryText)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(sound.displayName)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            // 2026-11-20 (#72): ▶ 바탕 원을 늘 보이게 — 예전엔 마우스를 올릴 때만 보여 버튼으로 덜 읽혔다.
            CircleIconButton(systemName: "play.fill", tint: palette.secondaryText,
                             soft: palette.accentSoft, size: 24,
                             font: .system(size: 9), restingOpacity: 1) {
                app.preview(sound)
            }
            .accessibilityLabel(Text("Preview \(sound.displayName)"))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
    }

    private var volumeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").foregroundStyle(palette.secondaryText).font(.system(size: 11))
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { settings.alarmVolume }, set: { settings.alarmVolume = $0 }), in: 0...1)
                    // 2026-08-21: same FILL-as-state-indicator mistake as the radio above —
                    // the filled part of the track was invisible against `surface`.
                    .tint(palette.controlIcon)
                    .accessibilityLabel("Alarm volume")
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(palette.secondaryText).font(.system(size: 11))
                    .accessibilityHidden(true)
            }
            note("The end is also shown visually, so a muted Mac still alerts you.")
        }
        .padding(12)
    }

    // MARK: When the timer ends · General

    private var endSection: some View {
        section("WHEN THE TIMER ENDS") {
            toggleRow("Repeat sound until dismissed", \.repeatUntilDismissed,
                      note: "Otherwise the alarm rings 3 times.")
            rowDivider
            toggleRow("Show notification", \.notificationsEnabled)
        }
    }

    private var generalSection: some View {
        section("GENERAL") {
            toggleRow("Show seconds in custom entry", \.showSeconds)
            rowDivider
            toggleRow("Show timer in menu bar", \.showInMenuBar)
            rowDivider
            toggleRow("Keep Mac awake while running", \.keepAwake)
        }
    }

    /// An explicit Binding straight off the @Observable store — avoids any
    /// @Bindable scoping subtleties so toggles reliably persist & apply.
    private func boolBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    /// Words on the left, the switch on the right edge — every switch in one column.
    /// 2026-11-20 (#72): 예전엔 스위치가 글자 끝에 붙어 줄마다 x 위치가 달랐다(지그재그). 긴 번역은 글만 줄바꿈된다.
    private func toggleRow(_ label: LocalizedStringKey, _ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>,
                           note noteText: LocalizedStringKey? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(palette.primaryText)
                    .fixedSize(horizontal: false, vertical: true)   // wrap long translations
                    .multilineTextAlignment(.leading)
                if let noteText { note(noteText) }
            }
            .accessibilityHidden(true)   // the switch below carries the same label
            Spacer(minLength: 0)
            Toggle(isOn: boolBinding(keyPath)) { Text(label) }
                .toggleStyle(PaletteSwitchStyle(on: palette.controlIcon,
                                                off: palette.primaryText.opacity(0.16),
                                                reduceMotion: reduceMotion))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Remove (#52)

    /// Deliberately quiet. A destructive control does not need to catch the eye in a
    /// list of preferences — the confirmation is where the weight belongs, and a red
    /// row here would pull attention every time someone came to change a theme.
    private var removeSection: some View {
        box {
            VStack(alignment: .leading, spacing: 3) {
                Button("Remove PomoLight…") { confirmRemoval() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                note("Moves PomoLight to the Trash and deletes what it saved.")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// A band across both columns, under a hairline.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(palette.primaryText.opacity(0.10)).frame(height: 0.5)
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
                    .font(.system(size: 12, design: .rounded))
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

    // MARK: Building blocks

    /// A section: a small title, then its rows in one rounded box.
    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(palette.secondaryText)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            box(content)
        }
    }

    /// Rows that belong together, grouped like tracks in an edit — a `surface` box on the `bg` page.
    private func box<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.primaryText.opacity(0.10), lineWidth: 0.5))
    }

    private var rowDivider: some View {
        Rectangle().fill(palette.primaryText.opacity(0.10)).frame(height: 0.5).padding(.leading, 12)
    }

    /// The small explanatory line under a control.
    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The "Done" pill: the buttonFill/buttonLabel pair, the one combination proven legible on every theme.
struct PillButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(label)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(fill))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

/// A switch whose OFF track is visible on the light surface too.
/// 2026-11-20 (#72): the system switch draws its off track so faint on `surface` that on and off read as one
/// strong state and one blank. Same shape and behaviour, our two track colours; VoiceOver still sees a switch.
struct PaletteSwitchStyle: ToggleStyle {
    let on: Color
    let off: Color
    var reduceMotion = false

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? on : off)
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
