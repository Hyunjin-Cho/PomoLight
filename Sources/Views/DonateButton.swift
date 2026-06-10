import SwiftUI

/// A quietly understated heart that opens the donation page. A free app asks
/// softly — the heart only beats when you reach for it.
struct DonateButton: View {
    let palette: Palette
    @State private var hovering = false
    @State private var beat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            beatOnce()
            if let url = URL(string: SettingsStore.donateURLString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Image(systemName: "heart.fill")
                .font(.system(size: 15))
                .foregroundStyle(palette.accent.opacity(hovering ? 1.0 : 0.7))
                .scaleEffect(beat ? 1.18 : (hovering && !reduceMotion ? 1.08 : 1.0))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.2), value: hovering)
        .help("Support PomoLight with a donation")
        .accessibilityLabel("Donate")
    }

    private func beatOnce() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { beat = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { beat = false }
        }
    }
}
