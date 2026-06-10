import AVFoundation

/// Pure DSP that renders gentle-but-unmistakable alarm tones into PCM buffers.
/// macOS system sounds are notification blips (they read as "button" sounds), so
/// PomoLight synthesizes its own alarms: each is a short motif of additive-sine
/// notes with a soft attack + exponential decay — pleasant, but clearly "time's up".
enum BellSynth {
    /// A timbre: inharmonic sine partials, each with its own amplitude + decay.
    private struct Partial { let ratio: Double; let amp: Double; let decay: Double }
    /// A note in the motif: when it starts (seconds) and its pitch (Hz).
    private struct Note { let start: Double; let freq: Double }
    private struct Voice {
        let partials: [Partial]
        let notes: [Note]
        let length: Double
        let attack: Double
        let gain: Float
    }

    // C5 523.25 · E5 659.25 · G5 783.99 · C6 1046.5 · E6 1318.5 · G4 392 · A5 880 · E4 330
    private static func voice(for sound: AlarmSound) -> Voice {
        switch sound {
        case .synthBell:   // "Soft Chime" — a calm rising arpeggio
            return Voice(
                partials: [Partial(ratio: 1, amp: 1.0, decay: 0.70), Partial(ratio: 2, amp: 0.45, decay: 0.45),
                           Partial(ratio: 3.01, amp: 0.22, decay: 0.30), Partial(ratio: 5.4, amp: 0.10, decay: 0.18)],
                notes: [Note(start: 0, freq: 523.25), Note(start: 0.20, freq: 659.25),
                        Note(start: 0.40, freq: 783.99), Note(start: 0.62, freq: 1046.5)],
                length: 1.35, attack: 0.006, gain: 0.72)

        case .marimba:     // warm, rounded wood — soft and calm (less "tok")
            return Voice(
                partials: [Partial(ratio: 1, amp: 1.0, decay: 0.62), Partial(ratio: 3.01, amp: 0.26, decay: 0.22),
                           Partial(ratio: 6.0, amp: 0.06, decay: 0.10)],
                notes: [Note(start: 0, freq: 329.63), Note(start: 0.24, freq: 392.0),
                        Note(start: 0.50, freq: 523.25)],
                length: 1.5, attack: 0.014, gain: 0.66)

        case .bell:        // soft, mellow bell — low and round, no piercing shimmer
            return Voice(
                partials: [Partial(ratio: 1, amp: 1.0, decay: 1.8), Partial(ratio: 2.0, amp: 0.38, decay: 1.1),
                           Partial(ratio: 3.0, amp: 0.12, decay: 0.55)],
                notes: [Note(start: 0, freq: 659.25), Note(start: 0.55, freq: 523.25)],
                length: 1.95, attack: 0.010, gain: 0.52)

        case .pulse:       // gentle, soft sine pulse — a calm "boo… boo", not a beep
            return Voice(
                partials: [Partial(ratio: 1, amp: 1.0, decay: 0.50), Partial(ratio: 2, amp: 0.05, decay: 0.20)],
                notes: [Note(start: 0, freq: 523.25), Note(start: 0.42, freq: 440.0)],
                length: 1.1, attack: 0.022, gain: 0.6)
        }
    }

    /// Renders one motif of the given alarm sound into a mono PCM buffer.
    static func makeBuffer(for sound: AlarmSound, sampleRate: Double = 44_100) -> AVAudioPCMBuffer? {
        let v = voice(for: sound)
        let frameCount = AVAudioFrameCount(v.length * sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let ampSum = v.partials.reduce(0) { $0 + $1.amp }
        let fadeStart = v.length - 0.10

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for note in v.notes where t >= note.start {
                let nt: Double = t - note.start
                for p in v.partials {
                    let env: Double
                    if nt < v.attack {
                        env = 0.5 * (1.0 - cos(Double.pi * nt / v.attack))   // soft raised-cosine attack
                    } else {
                        env = exp(-(nt - v.attack) / p.decay)                 // exponential decay
                    }
                    let phase: Double = 2.0 * Double.pi * note.freq * p.ratio * nt
                    sample += p.amp * env * sin(phase)
                }
            }
            sample /= ampSum * 1.5
            if t > fadeStart {
                sample *= max(0.0, (v.length - t) / 0.10)
            }
            let clamped: Double = max(-1.0, min(1.0, sample))
            channel[i] = Float(clamped) * v.gain
        }
        return buffer
    }
}
