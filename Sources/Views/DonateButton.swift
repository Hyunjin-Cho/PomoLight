import SwiftUI

/// A quietly understated heart that offers the donation options (Stats-style):
/// click → a small menu of ways to support (Toss for Korea, BMC internationally).
struct DonateButton: View {
    let palette: Palette
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Menu {
            ForEach(SettingsStore.donationLinks) { link in
                Button {
                    if let url = URL(string: link.urlString) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Text(verbatim: link.title)
                }
            }
        } label: {
            Image(systemName: "heart.fill")
                // 16, not the gear's 14: heart.fill inks smaller than gearshape.fill
                // at equal point size, so matching the numbers leaves the heart
                // visibly the lighter of the two in the top bar.
                .font(.system(size: 16))
                // secondaryText, matching the gear — NOT the accent this asked for
                // until 2026-08-20. Nobody had ever seen the accent version: the
                // AppKit cell below overrode it with its own near-black, so the
                // first build that honoured .foregroundStyle was also the first to
                // show what it actually looks like — 1.13:1 against the window on
                // Sky, where 3:1 is the floor for an icon. That is not "understated",
                // it is invisible, and it is not one bad theme: every accent in this
                // palette is a pastel picked to sit UNDER dark ink, which is exactly
                // why the gear beside it uses secondaryText (4.56:1) instead.
                .foregroundStyle(palette.secondaryText)
                .frame(width: 32, height: 32)
                .background(Circle().fill(palette.accentSoft.opacity(hovering ? 0.6 : 0)))
                .scaleEffect(hovering && !reduceMotion ? 1.06 : 1.0)
                .contentShape(Circle())
        }
        // 🚨 2026-08-20: was .menuStyle(.borderlessButton), which hands the label to
        // an AppKit pull-down cell that re-renders it as a template image. Two things
        // followed, both measured against the gear button beside it:
        //   · colour was the control's own near-black, rgb(34,36,36), not the theme
        //     accent — .foregroundStyle never reached the drawn glyph;
        //   · size was pinned to roughly 13 pt whatever .font() asked for. Rendering
        //     the same label at 15 pt and at 60 pt produced an identical 26x24 px
        //     heart, so the icon could not be enlarged at all through the label.
        // Beside a gear drawn at its true size in the theme colour, that reads as a
        // small dark smudge — the owner saw it as the heart being squeezed. It is not
        // squeezed: the inked aspect is 1.083 here and 1.083 when drawn correctly.
        // The .button style leaves the label in SwiftUI's hands, so both colour and
        // size are honoured; .buttonStyle(.plain) strips the bezel that style brings.
        // Hover now matches the gear's too (soft circle + 1.06), so the two controls
        // in this bar behave as a pair instead of each inventing its own feedback.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .help("Support PomoLight with a donation")
        .accessibilityLabel("Donate")
    }
}
