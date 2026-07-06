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
                .font(.system(size: 15))
                .foregroundStyle(palette.accent.opacity(hovering ? 1.0 : 0.7))
                .scaleEffect(hovering && !reduceMotion ? 1.08 : 1.0)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .help("Support PomoLight with a donation")
        .accessibilityLabel("Donate")
    }
}
