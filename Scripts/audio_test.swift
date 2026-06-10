#!/usr/bin/env swift
// Offline-renders the bell through the same AVAudioEngine graph the app uses and
// measures output RMS — proving the format fix makes sound (and that format:nil
// produced silence). No speakers needed. Run: swift Scripts/audio_test.swift
import AVFoundation

func makeBell(sampleRate: Double = 44_100) -> AVAudioPCMBuffer? {
    let partials: [(Double, Double, Double)] = [(1, 1, 1.6), (2, 0.55, 1.0), (2.76, 0.33, 0.6), (5.4, 0.18, 0.4)]
    let attack = 0.008, duration = 1.9, base = 528.0
    let frames = AVAudioFrameCount(duration * sampleRate)
    guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
          let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames),
          let ch = buf.floatChannelData?[0] else { return nil }
    buf.frameLength = frames
    let ampSum = partials.reduce(0) { $0 + $1.1 }
    for i in 0..<Int(frames) {
        let t = Double(i) / sampleRate
        var s = 0.0
        for p in partials {
            let env = t < attack ? 0.5 * (1 - cos(.pi * t / attack)) : exp(-(t - attack) / p.2)
            s += p.1 * env * sin(2 * .pi * base * p.0 * t)
        }
        ch[i] = Float(s / ampSum * 0.85)
    }
    return buf
}

func renderRMS(connectWithBufferFormat: Bool) -> Double {
    guard let bell = makeBell() else { return -1 }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: connectWithBufferFormat ? bell.format : nil)
    let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
    do {
        try engine.enableManualRenderingMode(.offline, format: outFmt, maximumFrameCount: 4096)
        try engine.start()
    } catch { return -2 }
    player.scheduleBuffer(bell, at: nil, options: [], completionHandler: nil)
    player.play()
    let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var sumSq = 0.0, count = 0
    let target: AVAudioFramePosition = 44_100   // 1 second
    while engine.manualRenderingSampleTime < target {
        let n = AVAudioFrameCount(min(4096, Int(target - engine.manualRenderingSampleTime)))
        do {
            let status = try engine.renderOffline(n, to: out)
            if status == .success, let d = out.floatChannelData?[0] {
                for i in 0..<Int(out.frameLength) { sumSq += Double(d[i] * d[i]); count += 1 }
            }
        } catch { return -3 }
    }
    engine.stop()
    return count > 0 ? (sumSq / Double(count)).squareRoot() : 0
}

// Note: connecting with format:nil throws at scheduleBuffer
// ("_outputFormat.channelCount == buffer.format.channelCount") — that was the
// silent-bell bug. We only measure the fixed (buffer-format) path here.
let fixRMS = renderRMS(connectWithBufferFormat: true)
print(String(format: "buffer fmt  RMS = %.6f", fixRMS))
if fixRMS > 0.001 {
    print("✅ Bell produces audio with the buffer-format connection.")
    exit(0)
} else {
    print("❌ Still silent — investigate.")
    exit(1)
}
