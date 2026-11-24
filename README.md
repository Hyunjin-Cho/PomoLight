<!-- 2026-11-24 (#33): cut from 211 lines to what someone downloading or building PomoLight needs. The longer text (feature history, every check explained, architecture) is in git history; each check script explains itself at the top. -->
# PomoLight 🍅✨

A calm, pastel **focus timer** for macOS. Free.

Pick any number of minutes, press Start, and a gentle bell chimes when time's up.

**[Download PomoLight](https://github.com/Hyunjin-Cho/PomoLight/releases/latest)**: open `PomoLight.dmg` and drag PomoLight into Applications. Requires macOS 14 or later on Apple Silicon. Signed and notarized by Apple.

## Features

- **Any duration**: presets (10 / 15 / 30 / 45 / 60 minutes), or type your own.
- **Gentle alarm**: five synthesized sounds, with preview and volume.
- **8 pastel themes**, each made for light and dark mode.
- **Menu-bar countdown** with mini controls. You can turn it off.
- **Stays accurate through sleep**: the timer follows the clock, not a counter.
- **29 languages**, following your system language.
- **Accessible**: WCAG-checked contrast (timer digits at least 7:1 in every theme), VoiceOver labels, Reduce Motion and keyboard shortcuts.
- **Quiet updates**: checks once a month and never pops up a window. An update installs only when you press Install.

Keyboard: **Space** start/pause · **R** reset · **1–5** presets · **⌘,** settings.

## Privacy

PomoLight collects nothing. It has no account, no analytics and no crash reporting.

Its only network access is the update check. About once a month, or when you press **Check Now**, it asks GitHub for the latest release. It downloads an update only when you press **Install New Version**.

You can turn the monthly check off in Settings ▸ Updates.

## Uninstall

**Settings ▸ Remove PomoLight…** moves the app to the Trash and deletes its settings.

If you drag the app to the Trash yourself, its settings file stays behind: `~/Library/Preferences/com.vismo.pomolight.plist`.

## Build from source

```bash
xcodegen generate && open PomoLight.xcodeproj   # then ⌘R
bash Scripts/verify.sh                          # build, unit tests and the app checks
```

Native SwiftUI, built with Xcode 26. It has zero third-party dependencies. In-app updates use [OnePercent](https://github.com/Hyunjin-Cho/OnePercent), the same author's MIT package.

To release:
1. Run `Scripts/build_app.sh`, then `Scripts/notarize.sh`.
2. Create a GitHub release tagged with the bare version (`1.1`).
3. Attach `PomoLight.dmg` and `PomoLight_<version>.zip`. The in-app updater downloads the ZIP.
4. Raise `CURRENT_PROJECT_VERSION` with every release.

## License

MIT. See [LICENSE](LICENSE).
