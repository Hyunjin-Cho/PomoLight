import AVFoundation

/// Pure DSP that renders gentle-but-unmistakable alarm tones into PCM buffers.
/// macOS system sounds are notification blips (they read as "button" sounds), so
/// PomoLight synthesizes its own alarms: each is a short motif of sine-partial
/// notes with a soft attack + exponential decay — pleasant, but clearly "time's up".
///
/// 🎵 2026-11-15 (#61) — all four voices were rewritten, on one rule:
/// **C major, and nothing but C, E and G — in the notes AND in the overtones —
/// rising, and coming to rest on the tonic.**
///
/// The owner's note was that the alarm sounded "a little minor, not quite right
/// for an ending". Measuring the old voices (FFT of the rendered buffers) showed
/// where that came from:
///   · Pulse was a falling C–B–A–G line. Its two loudest pitches were A4 and B4,
///     and it had no major third at all — it WAS minor-sounding, not just "a bit".
///   · Bell fell too (E5 → C5).
///   · Soft Chime and Marimba played major-triad notes, but their overtones sat at
///     3.01x and 5.4x — ratios that land between the notes of the chord. Rendered,
///     that put B, D, F and A above a C-major arpeggio (−17 to −32 dB): the wistful
///     shimmer of a bell, laid over what was meant to be a plain "done".
/// So every overtone below is an OCTAVE of its note (2x, 4x) and can only ever
/// add more C, E or G; every motif climbs; and every one ends on C.
/// `BellSynthTests` pins all three as things you can hear, not as bytes.
enum BellSynth {
    /// A timbre: sine overtones, each with its own amplitude + decay. Keep the
    /// ratios to powers of two — see the note above before adding a 3x or a 5x.
    private struct Partial { let ratio: Double; let amp: Double; let decay: Double }
    /// A note in the motif: when it starts (seconds), its pitch (Hz), how hard it
    /// is struck, and how long it rings compared with the voice's usual decay.
    private struct Note {
        let start: Double
        let freq: Double
        var amp: Double = 1.0
        var ring: Double = 1.0
    }
    private struct Voice {
        let partials: [Partial]
        let notes: [Note]
        let length: Double
        let attack: Double
    }

    // The only pitches any voice may use — the C major triad from G4 up to C6.
    private static let g4 = 392.00, c5 = 523.25, e5 = 659.25, g5 = 783.99, c6 = 1046.50

    private static func voice(for sound: AlarmSound) -> Voice {
        switch sound {
        case .synthBell:   // "Soft Chime" — do-mi-sol-do', each a touch brighter, the last left to ring
            return Voice(
                partials: [Partial(ratio: 1, amp: 1.0, decay: 0.75), Partial(ratio: 2, amp: 0.30, decay: 0.42),
                           Partial(ratio: 4, amp: 0.06, decay: 0.18)],
                notes: [Note(start: 0.00, freq: c5, amp: 0.80), Note(start: 0.15, freq: e5, amp: 0.86),
                        Note(start: 0.30, freq: g5, amp: 0.92), Note(start: 0.46, freq: c6, amp: 1.0, ring: 1.35)],
                length: 1.60, attack: 0.006)

        case .marimba:     // warm wood — sol-do-mi, then up to the tonic. The 4x is the mallet's "tok".
            return Voice(
                partials: [Partial(ratio: 1, amp: 1.0, decay: 0.45), Partial(ratio: 2, amp: 0.10, decay: 0.20),
                           Partial(ratio: 4, amp: 0.28, decay: 0.07)],
                notes: [Note(start: 0.00, freq: g4, amp: 0.85), Note(start: 0.13, freq: c5, amp: 0.90),
                        Note(start: 0.26, freq: e5, amp: 0.95), Note(start: 0.42, freq: c6, amp: 1.0, ring: 1.4)],
                length: 1.40, attack: 0.003)

        case .bell:        // two slow strikes — sol, then do with its major third on top
            return Voice(
                partials: [Partial(ratio: 1, amp: 1.0, decay: 1.5), Partial(ratio: 2, amp: 0.32, decay: 0.9),
                           Partial(ratio: 4, amp: 0.08, decay: 0.4)],
                notes: [Note(start: 0.00, freq: g4, amp: 0.90),
                        Note(start: 0.50, freq: c5, amp: 1.0), Note(start: 0.50, freq: e5, amp: 0.55)],
                length: 1.95, attack: 0.010)

        case .pulse:       // the plain timer — beep, beep, and a longer one a fourth higher
            return Voice(
                partials: [Partial(ratio: 1, amp: 1.0, decay: 0.14), Partial(ratio: 2, amp: 0.10, decay: 0.08)],
                notes: [Note(start: 0.00, freq: g5, amp: 0.90), Note(start: 0.22, freq: g5, amp: 0.90),
                        Note(start: 0.44, freq: c6, amp: 1.0, ring: 3.5)],
                length: 1.30, attack: 0.012)
        }
    }

    /// How loud every voice is: the RMS of its first second. One number for all
    /// four, so the volume slider means the same thing whichever voice is chosen —
    /// and so it still means what it meant before the rewrite (the old default
    /// voice measured 0.227 over the same second).
    private static let loudness = 0.22
    /// No sample may exceed this, whatever the loudness target asks for.
    private static let ceiling = 0.9

    /// Renders one motif of the given alarm sound into a mono PCM buffer.
    static func makeBuffer(for sound: AlarmSound, sampleRate: Double = 44_100) -> AVAudioPCMBuffer? {
        let v = voice(for: sound)
        let frameCount = AVAudioFrameCount(v.length * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let count = Int(frameCount)
        var samples = [Double](repeating: 0, count: count)
        let fadeStart = v.length - 0.10

        for i in 0..<count {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for note in v.notes where t >= note.start {
                let nt: Double = t - note.start
                for p in v.partials {
                    let env: Double
                    if nt < v.attack {
                        env = 0.5 * (1.0 - cos(Double.pi * nt / v.attack))        // soft raised-cosine attack
                    } else {
                        env = exp(-(nt - v.attack) / (p.decay * note.ring))       // exponential decay
                    }
                    let phase: Double = 2.0 * Double.pi * note.freq * p.ratio * nt
                    sample += note.amp * p.amp * env * sin(phase)
                }
            }
            if t > fadeStart {
                sample *= max(0.0, (v.length - t) / 0.10)
            }
            samples[i] = sample
        }

        // Level the voice by what it measures, not by a per-voice fudge factor.
        // 2026-11-15: this used to be `sample / (ampSum * 1.5)`, hard-clamped to
        // ±1 and scaled by a hand-picked gain — so overlapping notes could clip,
        // and the four voices sat at four different loudnesses (0.169–0.245).
        let window = min(count, Int(sampleRate))
        var energy = 0.0
        var peak = 0.0
        for i in 0..<count {
            if i < window { energy += samples[i] * samples[i] }
            peak = max(peak, abs(samples[i]))
        }
        let rms = (energy / Double(max(1, window))).squareRoot()
        guard rms > 0, peak > 0 else { return nil }
        let scale = min(loudness / rms, ceiling / peak)
        for i in 0..<count {
            channel[i] = Float(samples[i] * scale)
        }
        return buffer
    }
}
