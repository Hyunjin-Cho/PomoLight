import Foundation

/// The building blocks the alarm voices in `BellSynth` are made of: a struck-object
/// model, a filtered-saw pad, a small room, and the loudness meter + limiter that
/// level every voice to the same perceived volume.
///
/// 🎧 2026-11-17 (#61) — ported from the offline renderer the owner auditioned the
/// candidates with, OPERATION FOR OPERATION: same formulas, same order of arithmetic,
/// same noise seeds. That is the point of this file. The owner chose five voices by
/// ear from those renders, and the only way to be sure the app plays what they
/// heard is to produce the same samples. Checked when this was written: every
/// sample of all five voices equalled its audition file exactly, in an unoptimised
/// build and in an optimised one.
/// So a "tidy-up" that reorders a sum or swaps `exp` for a recurrence is a change to
/// the sound, not a refactor — re-render and re-listen before making one.
///
/// Everything is computed at 44.1 kHz (the reverb's delay lines are counted in
/// samples at that rate), which is also `ChimePlayer.format`.
enum AlarmDSP {
    static let sampleRate = 44_100.0
    private static let sr = sampleRate
    private static let twoPi = 2.0 * Double.pi

    /// Equal-tempered pitch of a MIDI note (A4 = 69 = 440 Hz).
    static func pitch(_ midi: Int) -> Double {
        440.0 * pow(2.0, Double(midi - 69) / 12.0)
    }

    /// A soft start (raised cosine): 0 → 1 over `a` seconds.
    @inline(__always) static func rise(_ t: Double, _ a: Double) -> Double {
        t >= a ? 1 : 0.5 * (1 - cos(Double.pi * t / a))
    }

    // MARK: - Struck objects (modal synthesis)

    /// One way the object vibrates: a multiple of the note's pitch, how strong it
    /// is, and how long it rings (time constant, seconds). A non-zero `beat` splits
    /// the mode into two, ±beat/2 Hz apart, so it slowly swells and fades the way a
    /// real steel shell or tine does.
    struct Mode { var ratio: Double; var amp: Double; var decay: Double; var beat: Double = 0 }

    /// The noise of the mallet, thumb, palm or stick touching it: noise kept between
    /// `bottom` and `top` Hz, gone in `decay` seconds.
    struct Strike { var amp: Double; var decay: Double; var top: Double; var bottom: Double }

    /// One hit in a motif: which note, when (s), how hard, and how long it rings
    /// compared with the voice's usual decay. A note outside the chord gets a short
    /// `ring` so it is gone before the last note — 2026-11-17, before that rule a
    /// passing tone was still sounding a semitone against the final note.
    struct Hit { var note: Int; var t: Double; var gain: Double; var ring: Double = 1 }

    /// xorshift64 — the strike noise, reproducible from its seed.
    private struct RNG {
        var s: UInt64
        mutating func next() -> Double {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            return Double(s >> 11) / Double(UInt64(1) << 53) * 2 - 1
        }
    }

    private static func strikeNoise(_ st: Strike, count: Int, seed: UInt64) -> [Double] {
        var r = RNG(s: seed | 1)
        var out = [Double](repeating: 0, count: count)
        let aTop = exp(-twoPi * st.top / sr), aBottom = exp(-twoPi * st.bottom / sr)
        var lp = 0.0, lpLow = 0.0
        for i in 0..<count {
            let t = Double(i) / sr
            let env = st.amp * rise(t, 0.0005) * exp(-t / st.decay)
            if t > 0.002 && env < 1e-7 { break }
            lp = (1 - aTop) * r.next() * env + aTop * lp
            lpLow = (1 - aBottom) * lp + aBottom * lpLow
            out[i] = lp - lpLow
        }
        return out
    }

    /// A struck object drawn as "which modes ring, how loudly, for how long".
    /// Higher notes ring shorter: every decay is scaled by (decayRef / f)^0.4.
    static func modal(_ midi: Int, _ modes: [Mode], attack: Double, length: Double,
                      strike: Strike? = nil, decayRef: Double = 523.25, ring: Double = 1,
                      seed: UInt64 = 7) -> [Double] {
        let f0 = pitch(midi)
        let k = pow(decayRef / f0, 0.4) * ring
        let n = Int(length * sr)
        var out = [Double](repeating: 0, count: n)
        for m in modes {
            let f = f0 * m.ratio
            guard f < 0.45 * sr else { continue }
            let parts: [(Double, Double)] = m.beat == 0
                ? [(f, m.amp)]
                : [(f - m.beat / 2, m.amp / 2), (f + m.beat / 2, m.amp / 2)]
            let decay = m.decay * k
            for (pf, pa) in parts {
                let w = twoPi * pf / sr
                for i in 0..<n {
                    let t = Double(i) / sr
                    let env = rise(t, attack) * exp(-t / decay)
                    if t > attack && env < 1e-6 { break }
                    out[i] += pa * env * sin(w * Double(i))
                }
            }
        }
        if let st = strike {
            let b = strikeNoise(st, count: n, seed: seed)
            for i in 0..<n { out[i] += b[i] }
        }
        return out
    }

    /// Lays a list of hits onto one track `length` seconds long; `make` renders hit
    /// number i.
    static func hits(_ length: Double, _ list: [Hit], _ make: (Hit, Int) -> [Double]) -> [Double] {
        var s = [Double](repeating: 0, count: Int(length * sr))
        for (index, h) in list.enumerated() {
            let x = make(h, index)
            let o = Int((h.t * sr).rounded())
            var i = 0
            while i < x.count && o + i < s.count { s[o + i] += h.gain * x[i]; i += 1 }
        }
        return s
    }

    // MARK: - Pad (filtered saws)

    @inline(__always) private static func polyBlep(_ t: Double, _ dt: Double) -> Double {
        if t < dt { let x = t / dt; return x + x - x * x - 1 }
        if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
        return 0
    }

    /// Three band-limited saws per note (−6, 0, +6 cents) through a low-pass filter
    /// that opens from 300 Hz and slowly closes again.
    /// 2026-11-17: the first render used two saws at ±7 cents — the sum nearly
    /// cancelled every half second and swelled back. A louder centre saw keeps
    /// those dips shallow.
    static func bloom(_ notes: [(midi: Int, gain: Double)], length: Double) -> [Double] {
        let n = Int(length * sr)
        var osc: [(dt: Double, g: Double)] = []
        for (midi, g) in notes {
            let f = pitch(midi)
            for (cents, w) in [(-6.0, 0.3), (0.0, 0.4), (6.0, 0.3)] { osc.append((f * pow(2, cents / 1200) / sr, g * w)) }
        }
        var phase = (0..<osc.count).map { Double($0) * 0.137 }.map { $0 - floor($0) }
        var ic1 = 0.0, ic2 = 0.0
        let kq = 1 / 0.85
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sr
            var x = 0.0
            for j in 0..<osc.count {
                x += osc[j].g * (2 * phase[j] - 1 - polyBlep(phase[j], osc[j].dt))
                phase[j] += osc[j].dt
                if phase[j] >= 1 { phase[j] -= 1 }
            }
            // Trapezoidal state-variable low-pass, cutoff swept per sample.
            let fc = 300 + 2400 * (1 - exp(-t / 0.25)) * exp(-t / 1.4)
            let g = tan(Double.pi * fc / sr)
            let a1 = 1 / (1 + g * (g + kq)), a2 = g * a1, a3 = g * a2
            let v3 = x - ic2
            let v1 = a1 * ic1 + a2 * v3
            let v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1; ic2 = 2 * v2 - ic2
            out[i] = rise(t, 0.12) * exp(-t / 2.0) * v2
        }
        return out
    }

    // MARK: - Room (Freeverb layout, mono)

    private static func reverb(_ x: [Double], wet: Double) -> [Double] {
        guard wet > 0 else { return x }
        let combLens = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
        let apLens = [556, 441, 341, 225]
        let room = 0.84, damp = 0.3, pre = Int(0.012 * sr)
        var combs = combLens.map { [Double](repeating: 0, count: $0) }
        var cIdx = [Int](repeating: 0, count: combLens.count)
        var store = [Double](repeating: 0, count: combLens.count)
        var aps = apLens.map { [Double](repeating: 0, count: $0) }
        var aIdx = [Int](repeating: 0, count: apLens.count)
        var out = x
        for i in 0..<x.count {
            let input = (i >= pre ? x[i - pre] : 0) * 0.015
            var acc = 0.0
            for c in 0..<combLens.count {
                let o = combs[c][cIdx[c]]
                store[c] = o * (1 - damp) + store[c] * damp
                combs[c][cIdx[c]] = input + store[c] * room
                cIdx[c] += 1; if cIdx[c] == combLens[c] { cIdx[c] = 0 }
                acc += o
            }
            for a in 0..<apLens.count {
                let b = aps[a][aIdx[a]]
                let o = -acc + b
                aps[a][aIdx[a]] = acc + b * 0.5
                aIdx[a] += 1; if aIdx[a] == apLens[a] { aIdx[a] = 0 }
                acc = o
            }
            out[i] = x[i] + wet * 3 * acc
        }
        return out
    }

    // MARK: - Loudness (ITU-R BS.1770 K-weighting)

    private struct Biquad {
        var b0, b1, b2, a1, a2: Double
        var z1 = 0.0, z2 = 0.0
        mutating func step(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    /// An approximation of the BS.1770 K-weighting pre-filter: a high shelf (+4 dB
    /// up top, the head's effect) and a high-pass at ~38 Hz.
    ///
    /// ⚠️ 2026-11-17, measured: this is NOT the exact standard filter. It takes the
    /// shelf's design values from libebur128 but builds the shelf with the RBJ
    /// cookbook formula, which shapes it differently — so a full-scale 997 Hz sine
    /// reads −3.27 LUFS here, where BS.1770 (and libebur128's own formula) read
    /// −3.01. It stays because it is the meter the owner's five voices were levelled
    /// with, and changing it moves them off the samples that were auditioned.
    /// What it costs, measured the same day: against an exact implementation, the
    /// five voices' levels relative to the old default agree within 0.11 dB.
    /// `BellSynthTests` pins the −3.27, so a change to this filter cannot slip in
    /// unnoticed.
    private static func kWeighted(_ x: [Double]) -> [Double] {
        var shelf: Biquad = {
            let G = 3.999843853973347, Q = 0.7071752369554196, fc = 1681.974450955533
            let A = pow(10, G / 40), w0 = twoPi * fc / sr, al = sin(w0) / (2 * Q), cw = cos(w0)
            let a0 = (A + 1) - (A - 1) * cw + 2 * sqrt(A) * al
            return Biquad(b0: A * ((A + 1) + (A - 1) * cw + 2 * sqrt(A) * al) / a0,
                          b1: -2 * A * ((A - 1) + (A + 1) * cw) / a0,
                          b2: A * ((A + 1) + (A - 1) * cw - 2 * sqrt(A) * al) / a0,
                          a1: 2 * ((A - 1) - (A + 1) * cw) / a0,
                          a2: ((A + 1) - (A - 1) * cw - 2 * sqrt(A) * al) / a0)
        }()
        var hp: Biquad = {
            let Q = 0.5003270373238773, fc = 38.13547087602444
            let w0 = twoPi * fc / sr, al = sin(w0) / (2 * Q), cw = cos(w0), a0 = 1 + al
            return Biquad(b0: (1 + cw) / 2 / a0, b1: -(1 + cw) / a0, b2: (1 + cw) / 2 / a0,
                          a1: -2 * cw / a0, a2: (1 - al) / a0)
        }()
        return x.map { hp.step(shelf.step($0)) }
    }

    /// How loud a short sound is to the ear, in LUFS: the loudest 400 ms window
    /// (stepped every 100 ms) of the K-weighted signal — BS.1770's "momentary"
    /// loudness, through the approximate filter above.
    static func loudness(_ x: [Double], window: Double = 0.4) -> Double {
        var k = kWeighted(x)
        let win = Int(window * sr), hop = Int(window / 4 * sr)
        if k.count < win { k += [Double](repeating: 0, count: win - k.count) }
        var best = -Double.infinity
        var start = 0
        while start + win <= k.count {
            var ms = 0.0
            for i in start..<(start + win) { ms += k[i] * k[i] }
            ms /= Double(win)
            best = max(best, -0.691 + 10 * log10(max(ms, 1e-20)))
            start += hop
        }
        return best
    }

    // MARK: - Levelling

    /// Holds the peaks under `ceiling` without touching the rest: a gain that dips
    /// 5 ms ahead of an over (1 ms attack) and recovers over 80 ms. Rendering is
    /// offline, so it can look ahead. Returns how deep it had to dip, in dB.
    private static func limit(_ x: [Double], ceiling: Double) -> (out: [Double], maxReductionDB: Double) {
        let n = x.count, look = Int(0.005 * sr)
        // The gain each sample would need on its own, and the smallest of those over
        // the next `look` samples. Almost every sample needs 1 (no change), so the
        // minimum is spread back only from the few that do not — the same values as
        // scanning every window, without 220 reads per sample.
        let need = x.map { min(1, ceiling / max(abs($0), 1e-12)) }
        var ahead = [Double](repeating: 1, count: n)
        for j in 0..<n where need[j] < 1 {
            for i in max(0, j - look)...j where need[j] < ahead[i] { ahead[i] = need[j] }
        }
        let aAtt = exp(-1 / (0.001 * sr)), aRel = exp(-1 / (0.08 * sr))
        var env = 1.0, deepest = 1.0
        var out = x
        for i in 0..<n {
            let g = ahead[i]
            env = g < env ? aAtt * env + (1 - aAtt) * g : aRel * env + (1 - aRel) * g
            deepest = min(deepest, env)
            out[i] = max(-ceiling, min(ceiling, x[i] * env))
        }
        return (out, -20 * log10(deepest))
    }

    /// Turns a raw motif into the finished ring: a touch of room, no DC, a clean
    /// start and a 120 ms fade-out, then levelled to `target` LUFS with peaks held
    /// under 0.9.
    ///
    /// The limiter may take at most 3 dB off a peak. 2026-11-17: allowed 6 dB, it
    /// took 4.4 dB off the electric piano and 6.4 dB off the wood blocks — that much
    /// flattens the attack. A voice that 3 dB cannot bring up to `target` stays a
    /// little quieter instead (Wood Blocks: about 1.4 dB, measured over 400 ms).
    static func finish(_ raw: [Double], length: Double, wet: Double, target: Double) -> [Double] {
        let n = Int(length * sr)
        var x = Array(raw.prefix(n))
        if x.count < n { x += [Double](repeating: 0, count: n - x.count) }
        x = reverb(x, wet: wet)
        var xp = 0.0, yp = 0.0
        for i in 0..<n { let y = x[i] - xp + 0.9986 * yp; xp = x[i]; yp = y; x[i] = y }   // DC blocker, ~10 Hz
        let fade = Int(0.12 * sr)
        for i in 0..<fade { x[n - fade + i] *= 0.5 * (1 + cos(Double.pi * Double(i + 1) / Double(fade))) }
        for i in 0..<Int(0.0005 * sr) { x[i] *= rise(Double(i) / sr, 0.0005) }
        // Level → limit → make up what the limiter took, a few times over.
        let base = x, maxRed = 3.0
        var gain = pow(10, (target - loudness(base)) / 20)
        var result: [Double] = []
        for _ in 0..<8 {
            var (out, red) = limit(base.map { $0 * gain }, ceiling: 0.9)
            if red > maxRed + 0.05 {
                gain *= pow(10, -(red - maxRed) / 20)
                (out, red) = limit(base.map { $0 * gain }, ceiling: 0.9)
            }
            result = out
            let miss = target - loudness(out)
            if abs(miss) < 0.05 { break }
            if miss > 0 && red >= maxRed - 0.05 { break }
            gain *= pow(10, miss / 20)
        }
        return result
    }
}
