import XCTest
import AVFoundation

/// The alarm voices, pinned by what they SOUND like — rewritten 2026-11-17 with the
/// five new voices (#61).
///
/// The rules before this (2026-11-15) were made for four sine-partial voices:
/// "nothing but C, E and G anywhere in the spectrum", "every voice climbs", and
/// "the loudest note at the end is C". The owner then chose five voices by ear that
/// break all three, and not by accident:
///   · real instruments carry overtones and strike noise that are not C, E or G —
///     a handpan's third mode on G4 is a D6, a wood block is inharmonic by nature;
///   · Kalimba walks DOWN, sol-mi-re-do;
///   · Handpan ends on its E, and in Kalimba's last half second the C sits 12 dB
///     under the E and G — its final C swells and fades (a 0.6 Hz beat) and is near
///     a null by then. Measured on the very samples the owner listened to.
/// What the five still share is pinned here, as things you can hear:
///   · what is left ringing is the C major chord — a note outside it is gone by then;
///   · they are equally loud to the ear;
///   · each is over before the next ring, and none of them clips or clicks.
///
/// That the app plays exactly what was auditioned was checked once, outside this
/// suite (every sample equal); this suite does not compare bytes, so a deliberate
/// change to a voice is free to pass it — by still sounding right.
///
/// Rendering is pure arithmetic into a buffer — no audio device is opened.
final class BellSynthTests: XCTestCase {

    private let sampleRate = 44_100.0

    /// The gap between two rings of an alarm. This mirrors `ChimePlayer.ringInterval`,
    /// which is private; if that changes, change this with it.
    private let ringInterval = 2.0

    /// Every voice ends in a 120 ms fade (`AlarmDSP.finish`).
    private let fadeOut = 0.12

    private static let pitchNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    /// C, E and G.
    private static let cMajorTriad: Set<Int> = [0, 4, 7]
    /// C4 … C7: where the notes and their audible overtones live.
    private static let semitones = 60...96

    // MARK: - Where it ends

    /// Whatever is still sounding in the last half second before the fade is the
    /// C major chord: every semitone within 20 dB of the loudest one is a C, an E or
    /// a G. A note outside the chord may pass through — Kalimba's D does — but it
    /// has to be gone by then.
    ///
    /// Measured 2026-11-17 (nearest note outside the chord, below the loudest):
    /// Wood Blocks 29 dB, Soft Synth 30, Handpan 39, Kalimba 41, Marimba 73.
    /// Checked the other way round the same day: with Kalimba's D left to ring as
    /// long as its other notes (`ring: 1`), this test fails on that D.
    func testWhatIsLeftRingingIsTheCMajorChord() throws {
        for sound in AlarmSound.allCases {
            let samples = try render(sound)
            let end = samples.count - Int(fadeOut * sampleRate)
            let start = end - Int(0.5 * sampleRate)
            let heard = levels(in: samples[start..<end]).filter { $0.dB > -20 }
            XCTAssertFalse(heard.isEmpty, "\(sound.rawValue): nothing is ringing at the end")
            for pitch in heard where !Self.cMajorTriad.contains(pitch.midi % 12) {
                XCTFail("\(sound.rawValue) is still ringing \(name(pitch.midi)) at " +
                        "\(String(format: "%.1f", pitch.dB)) dB at the end — outside the C major chord")
            }
        }
    }

    // MARK: - How loud, how long

    /// The volume slider must mean the same thing for every voice, so every voice
    /// is levelled to one loudness — the one the old default, Soft Chime, measured.
    ///
    /// Wood Blocks is the one exception, and a known one: it is four dry knocks,
    /// and the limiter that holds its peaks under 0.9 may take only 3 dB off them
    /// (more flattens the attack). It ends about 1.4 dB short on the 400 ms meter —
    /// within 1 dB on a 100 ms one, which suits a knock better. It was auditioned
    /// like that.
    func testAllVoicesAreEquallyLoud() throws {
        let target = BellSynth.targetLoudness
        for sound in AlarmSound.allCases {
            let measured = AlarmDSP.loudness(try render(sound).map(Double.init))
            if sound == .woodBlocks {
                XCTAssertLessThanOrEqual(measured, target + 0.1, "\(sound.rawValue) is at \(measured) LUFS")
                XCTAssertGreaterThanOrEqual(measured, target - 1.5, "\(sound.rawValue) is at \(measured) LUFS")
            } else {
                XCTAssertEqual(measured, target, accuracy: 0.1,
                               "\(sound.rawValue) is at \(measured) LUFS, the others at \(target)")
            }
        }
    }

    /// The meter above is the one the voices were chosen with — and it is only an
    /// approximation of BS.1770: a full-scale 997 Hz sine, which the standard reads
    /// as −3.01 LUFS, reads −3.27 on it (measured 2026-11-17; why is on
    /// `AlarmDSP.kWeighted`). Pinned so that "fixing" it is a decision: the
    /// difference between the voices barely moves (0.11 dB at most, measured), but
    /// every voice's samples do, and they are no longer the ones that were heard.
    func testTheLoudnessMeterIsTheOneTheVoicesWereLevelledWith() {
        let sine = (0..<Int(sampleRate)).map { sin(2 * Double.pi * 997 * Double($0) / sampleRate) }
        XCTAssertEqual(AlarmDSP.loudness(sine), -3.267, accuracy: 0.01)
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
            XCTAssertGreaterThanOrEqual(seconds, 1.0,
                                        "\(sound.rawValue) is over in \(seconds) s — too short to register as an alarm")
        }
    }

    // MARK: - Helpers

    /// The buffer the app would play.
    private func render(_ sound: AlarmSound, file: StaticString = #filePath, line: UInt = #line) throws -> [Float] {
        let buffer = try XCTUnwrap(BellSynth.makeBuffer(for: sound),
                                   "\(sound.rawValue) did not render", file: file, line: line)
        XCTAssertEqual(buffer.format.sampleRate, sampleRate, file: file, line: line)
        XCTAssertEqual(buffer.format.channelCount, 1, file: file, line: line)
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
