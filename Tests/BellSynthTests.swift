import XCTest
import AVFoundation
import Accelerate

/// The alarm voices, pinned by what they SOUND like — written 2026-11-15 with the
/// rewrite of `BellSynth` (#61).
///
/// Nothing here compares bytes. A recorded-buffer test would have passed happily on
/// the voices this replaced, and those were the problem: the owner heard the alarm
/// as "a little minor, not right for an ending", and measuring them showed why —
/// Pulse was a falling C–B–A–G line with A and B as its loudest pitches, Bell fell
/// too, and the other two carried overtones (3.01x, 5.4x) that put B, D, F and A
/// over a C-major arpeggio.
///
/// So the tests ask the questions a listener would: is it C major and only C major,
/// does it climb, does it come to rest on the tonic, is it as loud as its
/// neighbours, and is it over before the next ring starts. Each one is answered by
/// measuring the rendered samples (a spectrum for "what is in it", a Goertzel
/// filter per semitone for "which note is loudest right now"), so a new voice has
/// to pass them by sounding right, not by matching a table.
///
/// Checked the other way round on 2026-11-15: with the previous `BellSynth.swift`
/// put back, four of these six tests fail — everything except "does not clip" and
/// "is over before the next ring", which the old voices also satisfied.
///
/// Rendering is pure arithmetic into a buffer — no audio device is opened.
final class BellSynthTests: XCTestCase {

    private let sampleRate = 44_100.0

    /// The gap between two rings of an alarm. This mirrors `ChimePlayer.ringInterval`,
    /// which is private; if that changes, change this with it.
    private let ringInterval = 2.0

    private static let pitchNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    /// C, E and G — the only pitch classes a voice may contain.
    private static let cMajorTriad: Set<Int> = [0, 4, 7]
    /// C4 … C7: where the notes and their audible overtones live.
    private static let semitones = 60...96

    // MARK: - What it is made of

    /// The whole point of the rewrite. Every pitch a voice puts out — the notes AND
    /// the overtones — within 30 dB of its loudest must be a C, an E or a G, and
    /// must be IN TUNE (within 20 cents).
    ///
    /// This looks at the real spectrum (an FFT with a peak search), not at a grid of
    /// semitones, and that is deliberate: 2026-11-15, the first version of this test
    /// listened only at exact semitone frequencies, and the old voices' overtones
    /// (3.01x, 5.4x) slipped through it — they sat 8 and 20 cents AWAY from any
    /// semitone, which is exactly what made them sound off. Run against the old
    /// voices this now reports all of it: A4 and B4 at 0 dB in Pulse, D7/B6 at
    /// −17/−20 dB in Soft Chime, D6 in Marimba, B6 in Bell.
    func testEveryVoiceIsMadeOfCEAndGOnly() throws {
        for sound in AlarmSound.allCases {
            let found = spectralPeaks(in: try render(sound), within: 30)
            XCTAssertFalse(found.isEmpty, "\(sound.rawValue): no pitch found at all")
            for peak in found {
                let midi = 69 + 12 * log2(peak.hertz / 440)
                let nearest = Int(midi.rounded())
                let cents = (midi - Double(nearest)) * 100
                let described = "\(name(nearest)) \(cents >= 0 ? "+" : "")\(String(format: "%.0f", cents))¢ " +
                                "(\(String(format: "%.1f", peak.hertz)) Hz, \(String(format: "%.0f", peak.dB)) dB)"
                XCTAssertTrue(Self.cMajorTriad.contains(nearest % 12),
                              "\(sound.rawValue) contains \(described) — a voice may only contain C, E and G")
                XCTAssertLessThanOrEqual(abs(cents), 20,
                                         "\(sound.rawValue) contains \(described) — out of tune with the chord")
            }
        }
    }

    // MARK: - Where it goes

    /// An ending should arrive. Whatever is still ringing at the end of the motif,
    /// the loudest of it must be C — the tonic — not a note left hanging.
    func testEveryVoiceComesToRestOnTheTonic() throws {
        for sound in AlarmSound.allCases {
            let samples = try render(sound)
            // The last half second before the closing 0.1 s fade.
            let end = samples.count - Int(0.1 * sampleRate)
            let start = end - Int(0.5 * sampleRate)
            let loudest = try XCTUnwrap(levels(in: samples[start..<end]).max { $0.dB < $1.dB })
            XCTAssertEqual(loudest.midi % 12, 0,
                           "\(sound.rawValue) is left ringing on \(name(loudest.midi)), not on C")
        }
    }

    /// And it should arrive from below: the pitch it ends on is higher than the
    /// pitch it starts on. (The old Bell and Pulse both went down.)
    func testEveryVoiceClimbs() throws {
        for sound in AlarmSound.allCases {
            let samples = try render(sound)
            let opening = samples[0..<Int(0.12 * sampleRate)]
            let end = samples.count - Int(0.1 * sampleRate)
            let closing = samples[(end - Int(0.5 * sampleRate))..<end]
            let first = try XCTUnwrap(levels(in: opening).max { $0.dB < $1.dB })
            let last = try XCTUnwrap(levels(in: closing).max { $0.dB < $1.dB })
            XCTAssertGreaterThan(last.midi, first.midi,
                                 "\(sound.rawValue) starts on \(name(first.midi)) and ends on \(name(last.midi)) — it should rise")
        }
    }

    // MARK: - How loud, how long

    /// The volume slider must mean the same thing for every voice. The old four
    /// measured 0.169–0.245 over their first second; these are levelled to one value.
    func testAllVoicesAreEquallyLoud() throws {
        var measured: [(AlarmSound, Double)] = []
        for sound in AlarmSound.allCases {
            let samples = try render(sound)
            let window = samples.prefix(Int(sampleRate))
            let rms = (window.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(window.count)).squareRoot()
            measured.append((sound, rms))
        }
        for (sound, rms) in measured {
            // 0.22 is where the previous default voice sat (0.227), so a volume the
            // user already chose still sounds like the volume they chose.
            XCTAssertEqual(rms, 0.22, accuracy: 0.011, "\(sound.rawValue) is at \(rms) over its first second")
        }
    }

    /// Never clipped, and no click at either end: the first sample starts from
    /// silence and the last one has faded back into it.
    func testNoVoiceClipsOrClicks() throws {
        for sound in AlarmSound.allCases {
            let samples = try render(sound)
            let peak = samples.map { abs($0) }.max() ?? 0
            XCTAssertLessThanOrEqual(peak, 0.9001, "\(sound.rawValue) peaks at \(peak)")
            XCTAssertGreaterThan(peak, 0.3, "\(sound.rawValue) is nearly silent (peak \(peak))")
            XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.0001, "\(sound.rawValue) does not start from silence")
            XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.001, "\(sound.rawValue) does not end in silence")
        }
    }

    /// A repeating alarm rings every two seconds. A motif longer than that would be
    /// cut off by its own next ring.
    func testEveryVoiceIsOverBeforeTheNextRing() throws {
        for sound in AlarmSound.allCases {
            let seconds = Double(try render(sound).count) / sampleRate
            XCTAssertLessThan(seconds, ringInterval, "\(sound.rawValue) lasts \(seconds) s")
            XCTAssertGreaterThan(seconds, 1.0, "\(sound.rawValue) is over in \(seconds) s — too short to register as an alarm")
        }
    }

    // MARK: - Helpers

    private func render(_ sound: AlarmSound, file: StaticString = #filePath, line: UInt = #line) throws -> [Float] {
        let buffer = try XCTUnwrap(BellSynth.makeBuffer(for: sound),
                                   "\(sound.rawValue) did not render", file: file, line: line)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0], file: file, line: line)
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    private func name(_ midi: Int) -> String {
        "\(Self.pitchNames[midi % 12])\(midi / 12 - 1)"
    }

    /// How strong each semitone from C4 to C7 is in a stretch of samples, in dB
    /// relative to the strongest of them.
    private func levels(in samples: ArraySlice<Float>) -> [(midi: Int, dB: Double)] {
        let count = samples.count
        guard count > 1 else { return [] }
        // One Hann window for the whole stretch, so a pitch that is merely NEAR a
        // semitone does not smear into it.
        var windowed = [Double](repeating: 0, count: count)
        for (i, sample) in samples.enumerated() {
            let hann = 0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(count - 1)))
            windowed[i] = Double(sample) * hann
        }
        let powers: [(Int, Double)] = Self.semitones.map { midi in
            let hertz = 440 * pow(2, Double(midi - 69) / 12)
            return (midi, goertzel(windowed, hertz: hertz))
        }
        let strongest = powers.map(\.1).max() ?? 0
        guard strongest > 0 else { return [] }
        return powers.map { (midi: $0.0, dB: 10 * log10(max($0.1, 1e-30) / strongest)) }
    }

    /// Every distinct pitch in the signal that is within `range` dB of the loudest
    /// one, wherever it falls — on a semitone or between two. A Hann-windowed FFT
    /// (0.34 Hz per bin) and a search for local maxima between 100 Hz and 9 kHz.
    private func spectralPeaks(in samples: [Float], within range: Double) -> [(hertz: Double, dB: Double)] {
        let log2n = vDSP_Length(17)
        let n = 1 << 17
        let count = min(samples.count, n)
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        var padded = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &padded, 1, vDSP_Length(count))

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }
        var real = [Float](repeating: 0, count: n / 2)
        var imaginary = [Float](repeating: 0, count: n / 2)
        var power = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                padded.withUnsafeBufferPointer { paddedPointer in
                    paddedPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }

        let binWidth = sampleRate / Double(n)
        let low = Int(100 / binWidth), high = Int(9_000 / binWidth)
        let reach = 40    // ±13 Hz: closer than any two pitches a voice could sensibly use
        var peaks: [(bin: Int, power: Float)] = []
        for bin in low..<high {
            let here = power[bin]
            var isPeak = here > 0
            if isPeak {
                for other in max(low, bin - reach)...min(high, bin + reach) where power[other] > here {
                    isPeak = false
                    break
                }
            }
            if isPeak { peaks.append((bin, here)) }
        }
        guard let strongest = peaks.map(\.power).max(), strongest > 0 else { return [] }
        return peaks
            .map { (hertz: Double($0.bin) * binWidth, dB: 10 * log10(Double($0.power / strongest))) }
            .filter { $0.dB > -range }
    }

    /// The power of a single frequency in a signal (the Goertzel recurrence).
    private func goertzel(_ signal: [Double], hertz: Double) -> Double {
        let coefficient = 2 * cos(2 * Double.pi * hertz / sampleRate)
        var previous = 0.0, beforeThat = 0.0
        for sample in signal {
            let current = sample + coefficient * previous - beforeThat
            beforeThat = previous
            previous = current
        }
        return previous * previous + beforeThat * beforeThat - coefficient * previous * beforeThat
    }
}
