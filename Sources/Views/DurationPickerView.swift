import SwiftUI

/// The idle-state duration controls: quick preset chips plus a free "Custom"
/// entry that accepts any value (the owner's "freely choose any minutes" rule).
struct DurationPickerView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(SettingsStore.self) private var settings
    @Environment(AppModel.self) private var app
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
            // Editing ended — 0:00 in the fields snaps to the engine's floor.
            if focus == nil { snapFieldsToFloor() }
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
        HStack(spacing: 6) {
            CircleIconButton(systemName: "minus", tint: palette.secondaryText,
                             soft: palette.accentSoft, size: 28,
                             font: .system(size: 12, weight: .bold)) {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                pushToEngine()
            }
            VStack(spacing: 0) {
                TextField("", value: value, format: .number)
                    .focused($focusedField, equals: field)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 17, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(palette.primaryText)
                    .frame(width: width)
                    .onChange(of: value.wrappedValue) { _, _ in pushToEngine() }
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
            }
        }
    }

    private func select(minutes m: Int) {
        showingCustom = false
        engine.setMinutes(Double(m))
        settings.lastDurationMinutes = Double(m)
        app.publishSnapshot()
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
        settings.lastDurationMinutes = Double(total) / 60
        app.publishSnapshot()
        // Mid-typing the fields may briefly read 0:00 — leave them alone while
        // focused, but snap button-driven changes to the floor immediately.
        if focusedField == nil { snapFieldsToFloor() }
    }

    /// The engine never goes below its floor, but the FIELDS could keep showing
    /// 0:00 after editing — make them show the value the engine actually holds.
    private func snapFieldsToFloor() {
        guard showingCustom, minutes == 0, seconds == 0 else { return }
        if settings.showSeconds { seconds = 1 } else { minutes = 1 }
        // (the field's onChange re-runs pushToEngine, which is now a no-op)
    }
}
