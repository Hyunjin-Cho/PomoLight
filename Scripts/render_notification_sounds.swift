#!/usr/bin/env swift
// Renders the four synthesized alarm voices to .caf files so LOCAL NOTIFICATIONS
// can play them when the app isn't running (widgets can't play audio; notification
// sounds are looked up in the app bundle). Mirrors Sources/Audio/BellSynth.swift.
// Run after changing a voice:  swift Scripts/render_notification_sounds.swift
import AVFoundation

struct Partial { let ratio: Double; let amp: Double; let decay: Double }
struct Note { let start: Double; let freq: Double }
struct Voice {
    let file: String
    let partials: [Partial]
    let notes: [Note]
    let length: Double
    let attack: Double
    let gain: Float
}

let voices: [Voice] = [
    Voice(file: "SoftChime",
          partials: [Partial(ratio: 1, amp: 1.0, decay: 0.70), Partial(ratio: 2, amp: 0.45, decay: 0.45),
                     Partial(ratio: 3.01, amp: 0.22, decay: 0.30), Partial(ratio: 5.4, amp: 0.10, decay: 0.18)],
          notes: [Note(start: 0, freq: 523.25), Note(start: 0.20, freq: 659.25),
                  Note(start: 0.40, freq: 783.99), Note(start: 0.62, freq: 1046.5)],
          length: 1.35, attack: 0.006, gain: 0.72),
    Voice(file: "Marimba",
          partials: [Partial(ratio: 1, amp: 1.0, decay: 0.62), Partial(ratio: 3.01, amp: 0.26, decay: 0.22),
                     Partial(ratio: 6.0, amp: 0.06, decay: 0.10)],
          notes: [Note(start: 0, freq: 329.63), Note(start: 0.24, freq: 392.0), Note(start: 0.50, freq: 523.25)],
          length: 1.5, attack: 0.014, gain: 0.66),
    Voice(file: "Bell",
          partials: [Partial(ratio: 1, amp: 1.0, decay: 1.8), Partial(ratio: 2.0, amp: 0.38, decay: 1.1),
                     Partial(ratio: 3.0, amp: 0.12, decay: 0.55)],
          notes: [Note(start: 0, freq: 659.25), Note(start: 0.55, freq: 523.25)],
          length: 1.95, attack: 0.010, gain: 0.52),
    Voice(file: "Pulse",
          partials: [Partial(ratio: 1, amp: 1.0, decay: 0.50), Partial(ratio: 2, amp: 0.05, decay: 0.20)],
          notes: [Note(start: 0, freq: 523.25), Note(start: 0.28, freq: 493.88),
                  Note(start: 0.56, freq: 440.0), Note(start: 0.84, freq: 392.0)],
          length: 1.5, attack: 0.022, gain: 0.6),
]

let sr = 44_100.0
let outDir = "Resources/NotificationSounds"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

for v in voices {
    let frames = AVAudioFrameCount(v.length * sr)
    let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
    let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
    buf.frameLength = frames
    let ch = buf.floatChannelData![0]
    let ampSum = v.partials.reduce(0) { $0 + $1.amp }
    let fadeStart = v.length - 0.10
    for i in 0..<Int(frames) {
        let t = Double(i) / sr
        var s = 0.0
        for note in v.notes where t >= note.start {
            let nt = t - note.start
            for p in v.partials {
                let env: Double = nt < v.attack
                    ? 0.5 * (1.0 - cos(Double.pi * nt / v.attack))
                    : exp(-(nt - v.attack) / p.decay)
                s += p.amp * env * sin(2.0 * Double.pi * note.freq * p.ratio * nt)
            }
        }
        s /= ampSum * 1.5
        if t > fadeStart { s *= max(0.0, (v.length - t) / 0.10) }
        ch[i] = Float(max(-1.0, min(1.0, s))) * v.gain
    }
    let url = URL(fileURLWithPath: "\(outDir)/\(v.file).caf")
    try? FileManager.default.removeItem(at: url)
    let file = try AVAudioFile(forWriting: url, settings: fmt.settings,
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buf)
    print("wrote \(url.path)")
}
print("done")
