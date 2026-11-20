import SwiftUI

/// The idle-state duration controls: quick preset chips plus a free "Custom"
/// entry that accepts any value (the owner's "freely choose any minutes" rule).
struct DurationPickerView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings
    // 2026-08-21: an unused `@Environment(AppModel.self)` was declared here too —
    // same false requirement as the one removed from RootView.
    let palette: Palette

    private enum Field { case minutes, seconds }

    private let presets = [10, 15, 30, 45, 60]
    @State private var showingCustom = false
    @State private var minutes = 25
    @State private var seconds = 0
    @FocusState private var focusedField: Field?

    private var currentMinutes: Int { Int(engine.configuredDuration) / 60 }
    private var currentSeconds: Int { Int(engine.configuredDuration) % 60 }

    var body: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                chipRow(spacing: 8, hPad: 13)
                chipRow(spacing: 5, hPad: 9)
            }

            if showingCustom {
                customEntry
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showingCustom)
        .onChange(of: settings.showSeconds) { _, on in
            // Hidden seconds must not keep affecting the timer once seconds are off.
            if !on {
                seconds = 0
                if showingCustom { pushToEngine() }
            }
        }
        .onChange(of: focusedField) { _, focus in
            // Editing ended — show what the engine actually took, and persist once.
            if focus == nil {
                syncFieldsToEngine()
                persistChosenDuration()
            }
        }
    }

    private func chipRow(spacing: CGFloat, hPad: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(Array(presets.enumerated()), id: \.element) { index, m in
                let chip = PresetChip(title: "\(m)",
                                      selected: !showingCustom && currentMinutes == m && currentSeconds == 0,
                                      palette: palette, hPadding: hPad) {
                    select(minutes: m)
                }
                .help("\(m) minutes")
                // Number-key shortcuts are disabled while the custom field is open,
                // so typing e.g. "15" goes into the field instead of picking presets.
                if showingCustom {
                    chip
                } else {
                    chip.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                }
            }
            PresetChip(title: String(localized: "Custom"), selected: showingCustom, palette: palette, hPadding: hPad) {
                toggleCustom()
            }
            .help("Set any duration")
        }
    }

    private var customEntry: some View {
        HStack(spacing: 10) {
            stepperField(value: $minutes, field: .minutes, range: 0...999, width: 56, label: "min")
            if settings.showSeconds {
                Text(":").foregroundStyle(palette.secondaryText)
                stepperField(value: $seconds, field: .seconds, range: 0...59, width: 48, label: "sec")
            }
        }
    }

    private func stepperField(value: Binding<Int>, field: Field, range: ClosedRange<Int>,
                              width: CGFloat, label: LocalizedStringKey) -> some View {
        // 2026-11-20 (#70 F-8): VoiceOver read these as "Remove" / "Add" — the names SwiftUI takes
        // from the minus/plus symbols (measured through the AX API) — the same for the minutes and
        // the seconds pair, and "Remove" next to a duration sounds like deleting something.
        let less: LocalizedStringKey = field == .minutes ? "One minute less" : "One second less"
        let more: LocalizedStringKey = field == .minutes ? "One minute more" : "One second more"
        return HStack(spacing: 6) {
            CircleIconButton(systemName: "minus", tint: palette.secondaryText,
                             soft: palette.accentSoft, size: 28,
                             font: .system(size: 12, weight: .bold)) {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                pushToEngine()
                persistChosenDuration()
            }
            .accessibilityLabel(less)
            VStack(spacing: 0) {
                TextField("", value: value, format: .number)
                    .focused($focusedField, equals: field)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.primaryText)
                    .frame(width: width)
                    .onChange(of: value.wrappedValue) { _, _ in pushToEngine() }
                    .accessibilityLabel(label)   // "min" / "sec" — the field had no name at all
                Text(label)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 12).fill(palette.bg))
            CircleIconButton(systemName: "plus", tint: palette.secondaryText,
                             soft: palette.accentSoft, size: 28,
                             font: .system(size: 12, weight: .bold)) {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                pushToEngine()
                persistChosenDuration()
            }
            .accessibilityLabel(more)
        }
    }

    private func select(minutes m: Int) {
        showingCustom = false
        engine.setMinutes(Double(m))
        settings.lastDurationMinutes = Double(m)
    }

    private func toggleCustom() {
        showingCustom.toggle()
        if showingCustom {
            minutes = currentMinutes
            seconds = currentSeconds
            DispatchQueue.main.async { focusedField = .minutes }
        }
    }

    private func pushToEngine() {
        let m = min(max(minutes, 0), 999)
        let s = settings.showSeconds ? min(max(seconds, 0), 59) : 0
        // Write the clamped values back so the field can't show a value the engine
        // didn't actually use (e.g. typing 5000 → clamps to 999).
        if m != minutes { minutes = m }
        if s != seconds { seconds = s }
        // Floor: 1 second with the seconds field, a whole minute without it —
        // "0" in minutes-only mode must not silently mean a 1-second timer.
        let total = max(settings.showSeconds ? 1 : 60, m * 60 + s)
        engine.setDuration(seconds: Double(total))
        // Mid-typing the fields may briefly read 0:00 — leave them alone while
        // focused. 2026-08-21: persisting moved in here too. It used to run on every
        // keystroke (`lastDurationMinutes` writes through to UserDefaults on `didSet`),
        // so typing "120" wrote 1, then 12, then 120.
        // 2026-11-20 (#67): 위 주석은 "버튼으로 바꾼 값은 지금도 바로 저장된다"고 했지만
        // 사실이 아니었다. Custom 을 열면 분 칸에 포커스가 가고 −/+ 버튼은 포커스를
        // 가져가지 않으므로, 버튼으로 바꿔도 이 조건에 막혀 저장되지 않았다. 게다가
        // 포커스가 있는 채 시작을 누르면 이 뷰가 사라지면서 `onChange(of: focusedField)`
        // 도 돌지 않아, 다음 리셋·끄기에서 옛 저장값으로 되돌아갔다.
        // 지금은 세 곳에서 저장한다 — 시작할 때(`AppModel.startTimer()`, 빠짐없이
        // 잡는 곳), 포커스가 빠질 때, −/+ 버튼을 누를 때. 키 하나마다 쓰지 않는다는
        // #46 의 목적은 그대로다: 타이핑 중에는 여기서 저장하지 않는다.
        if focusedField == nil {
            syncFieldsToEngine()
            persistChosenDuration()
        }
    }

    /// Make the fields show the value the engine actually holds.
    ///
    /// 2026-08-21: this was `snapFieldsToFloor()` and only handled the bottom end, so
    /// entering 999:59 left the fields reading 999:59 while the engine held its 999:00
    /// ceiling — a 59-second lie. Reading back from the engine covers both ends with
    /// one rule, and there is only one place that decides what the duration is.
    private func syncFieldsToEngine() {
        guard showingCustom else { return }
        let total = Int(engine.configuredDuration.rounded())
        let m = total / 60
        let s = settings.showSeconds ? total % 60 : 0
        if minutes != m { minutes = m }
        if seconds != s { seconds = s }
        // (a field's onChange re-runs pushToEngine, which is now a no-op)
    }

    /// Persist the duration the engine settled on — never the raw field contents, so
    /// a clamped entry can't be remembered as something the engine would refuse.
    private func persistChosenDuration() {
        settings.lastDurationMinutes = engine.configuredDuration / 60
    }
}
