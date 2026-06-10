import AVFoundation

/// Pure DSP that renders a gentle-but-unmistakable alarm chime into a PCM buffer.
///
/// A single soft bell reads as a *notification*, not an *alarm*. So the alarm is a
/// short rising arpeggio (a calm music-box motif) — pleasant, but clearly "time's
/// up" rather than a passing ping. Each note is additive synthesis: a few
/// inharmonic sine partials with a soft attack and exponential decay (higher
/// partials decay faster, like a real struck bell), so it stays warm.
enum BellSynth {
    private struct Partial { let ratio: Double; let amp: Double; let decay: Double }

    private static let partials: [Partial] = [
        Partial(ratio: 1.00, amp: 1.00, decay: 0.70),
        Partial(ratio: 2.00, amp: 0.45, decay: 0.45),
        Partial(ratio: 3.01, amp: 0.22, decay: 0.30),
        Partial(ratio: 5.40, amp: 0.10, decay: 0.18),
    ]

    // A gentle rising motif (C5 · E5 · G5 · C6) — clearly an alarm, never harsh.
    private static let motif: [(start: Double, freq: Double)] = [
        (0.00, 523.25),   // C5
        (0.20, 659.25),   // E5
        (0.40, 783.99),   // G5
        (0.62, 1046.50),  // C6
    ]
    private static let motifLength = 1.35   // seconds (last note + tail)

    /// One full alarm motif. `gain` is the peak amplitude (0...1).
    static func makeAlarmBuffer(sampleRate: Double = 44_100, gain: Float = 0.7) -> AVAudioPCMBuffer? {
        let attack = 0.006
        let frameCount = AVAudioFrameCount(motifLength * sampleRate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let ampSum = partials.reduce(0) { $0 + $1.amp }
        let fadeStart = motifLength - 0.12

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for note in motif where t >= note.start {
                let nt = t - note.start
                for p in partials {
                    let envelope: Double
                    if nt < attack {
                        envelope = 0.5 * (1 - cos(.pi * nt / attack))
                    } else {
                        envelope = exp(-(nt - attack) / p.decay)
                    }
                    sample += p.amp * envelope * sin(2 * .pi * note.freq * p.ratio * nt)
                }
            }
            sample /= ampSum * 1.6
            if t > fadeStart { sample *= (motifLength - t) / 0.12 }
            channel[i] = Float(max(-1, min(1, sample))) * gain
        }
        return buffer
    }
}
