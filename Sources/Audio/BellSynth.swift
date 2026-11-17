import AVFoundation

/// Renders the alarm voices into PCM buffers. macOS system sounds are notification
/// blips (they read as "button" sounds), so PomoLight synthesizes its own alarms.
///
/// 🎧 2026-11-17 (#61) — five new voices, chosen by the owner by ear.
/// The four before them (Soft Chime, Marimba, Bell, Pulse) were all one engine: a
/// few sine partials with an exponential decay, and their overtones limited to
/// octaves. After those were retuned to plain C major (2026-11-15) the owner found
/// them fine, but still "a conversion of the sound we already had — that feels like
/// a limit", and asked for sounds made new. So these are built from what the real
/// instruments do: a struck bar, a plucked tine, a steel shell and a hollow block
/// are each modelled by how they vibrate (`AlarmDSP.modal`), and the pad is three
/// detuned saws through a sweeping filter (`AlarmDSP.bloom`). Eleven candidates
/// were rendered; the owner kept these five.
///
/// The name `BellSynth` is older than the voices — none of them is a bell now.
///
/// What every voice keeps, whatever its timbre (pinned in `BellSynthTests`):
///   · it leaves a C major chord ringing — a note outside it (Kalimba's D) is
///     struck short so it is gone before the end,
///   · it is as loud to the ear as every other voice,
///   · it is over before the next ring, two seconds later.
enum BellSynth {
    private typealias Hit = AlarmDSP.Hit
    private typealias Mode = AlarmDSP.Mode
    private typealias Strike = AlarmDSP.Strike

    // MIDI note numbers.
    private static let c4 = 60, g4 = 67, c5 = 72, d5 = 74, e5 = 76, g5 = 79, c6 = 84

    /// How loud every voice is to the ear, on `AlarmDSP.loudness`'s meter (LUFS). It
    /// is what Soft Chime — the default voice before these — measured, so a volume
    /// the user already chose still sounds like the volume they chose. All five
    /// auditioned candidates were levelled to this same number. (On an exact BS.1770
    /// meter Soft Chime reads −11.89 — see the note on `AlarmDSP.kWeighted`.)
    static let targetLoudness = -12.085901126425764

    private struct Voice {
        let length: Double
        let wet: Double
        let render: () -> [Double]
    }

    private static func voice(for sound: AlarmSound) -> Voice {
        switch sound {
        case .marimba:     // rosewood bars (modes tuned 1:4:10, as real marimba bars are) — rolled up G4 C5 E5 G5 C6
            return Voice(length: 1.5, wet: 0.06) {
                let modes = [Mode(ratio: 1, amp: 1, decay: 0.50), Mode(ratio: 4, amp: 0.28, decay: 0.08),
                             Mode(ratio: 10, amp: 0.08, decay: 0.025)]
                let mallet = Strike(amp: 0.10, decay: 0.004, top: 2500, bottom: 200)
                return AlarmDSP.hits(1.5, [Hit(note: g4, t: 0, gain: 0.75), Hit(note: c5, t: 0.065, gain: 0.8),
                                           Hit(note: e5, t: 0.13, gain: 0.85), Hit(note: g5, t: 0.195, gain: 0.9),
                                           Hit(note: c6, t: 0.26, gain: 1.0)]) { h, i in
                    AlarmDSP.modal(h.note, modes, attack: 0.002, length: 1.5, strike: mallet, ring: h.ring,
                                   seed: UInt64(11 + i))
                }
            }

        case .kalimba:     // steel tines (a cantilever's 2nd mode, tuned to 6x) — down sol-mi-re-do; the re is struck short
            return Voice(length: 1.6, wet: 0.10) {
                let modes = [Mode(ratio: 1, amp: 1, decay: 0.70, beat: 0.6), Mode(ratio: 2, amp: 0.05, decay: 0.2),
                             Mode(ratio: 6, amp: 0.20, decay: 0.05)]
                let thumb = Strike(amp: 0.05, decay: 0.006, top: 1500, bottom: 120)
                return AlarmDSP.hits(1.6, [Hit(note: g5, t: 0, gain: 0.85), Hit(note: e5, t: 0.14, gain: 0.85),
                                           Hit(note: d5, t: 0.28, gain: 0.9, ring: 0.3),
                                           Hit(note: c5, t: 0.42, gain: 1.0)]) { h, i in
                    AlarmDSP.modal(h.note, modes, attack: 0.003, length: 1.6, strike: thumb, ring: h.ring,
                                   seed: UInt64(41 + i))
                }
            }

        case .handpan:     // a steel shell (modes 1:2:3, each a slowly beating pair) — the low "ding" C4, then up G4 C5 E5
            return Voice(length: 1.9, wet: 0.16) {
                let modes = [Mode(ratio: 1, amp: 1, decay: 1.0, beat: 0.8), Mode(ratio: 2, amp: 0.5, decay: 0.65, beat: 1.2),
                             Mode(ratio: 3, amp: 0.2, decay: 0.35, beat: 1.6)]
                let palm = Strike(amp: 0.10, decay: 0.012, top: 600, bottom: 60)
                return AlarmDSP.hits(1.9, [Hit(note: c4, t: 0, gain: 0.9), Hit(note: g4, t: 0.16, gain: 0.85),
                                           Hit(note: c5, t: 0.32, gain: 0.9), Hit(note: e5, t: 0.48, gain: 1.0)]) { h, i in
                    AlarmDSP.modal(h.note, modes, attack: 0.006, length: 1.9, strike: palm, ring: h.ring,
                                   seed: UInt64(71 + i))
                }
            }

        case .woodBlocks:  // hollow wood (inharmonic 1 : 2.62 : 4.4, very short) — knock-knock, knock-knock: G5 C6 … G5 C6
            return Voice(length: 1.0, wet: 0.08) {
                let modes = [Mode(ratio: 1, amp: 1, decay: 0.06), Mode(ratio: 2.62, amp: 0.3, decay: 0.02),
                             Mode(ratio: 4.4, amp: 0.12, decay: 0.01)]
                let stick = Strike(amp: 0.22, decay: 0.0025, top: 4000, bottom: 600)
                return AlarmDSP.hits(1.0, [Hit(note: g5, t: 0, gain: 0.85), Hit(note: c6, t: 0.12, gain: 1.0),
                                           Hit(note: g5, t: 0.36, gain: 0.85), Hit(note: c6, t: 0.48, gain: 1.0)]) { h, i in
                    AlarmDSP.modal(h.note, modes, attack: 0.0008, length: 1.0, strike: stick, ring: h.ring,
                                   seed: UInt64(91 + i))
                }
            }

        case .softSynth:   // filtered saws — a C4·C5·E5·G5 chord that blooms open over 0.12 s
            return Voice(length: 1.85, wet: 0.20) {
                AlarmDSP.bloom([(c4, 0.45), (c5, 0.8), (e5, 0.7), (g5, 0.7)], length: 1.85)
            }
        }
    }

    /// The finished samples of one ring, before they become a buffer.
    static func samples(for sound: AlarmSound) -> [Double] {
        let v = voice(for: sound)
        return AlarmDSP.finish(v.render(), length: v.length, wet: v.wet, target: targetLoudness)
    }

    /// Renders one ring of the given alarm sound into a mono 44.1 kHz PCM buffer —
    /// the format `ChimePlayer` connects its player with.
    static func makeBuffer(for sound: AlarmSound) -> AVAudioPCMBuffer? {
        let ring = samples(for: sound)
        guard !ring.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: AlarmDSP.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ring.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(ring.count)
        for i in 0..<ring.count { channel[i] = Float(ring[i]) }
        return buffer
    }
}
