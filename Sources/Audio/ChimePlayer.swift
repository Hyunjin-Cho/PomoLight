import AVFoundation

/// Plays the gentle alarm. Every sound is synthesized in-app (a short motif played
/// twice); "repeat until dismissed" re-chimes on an interval until Dismiss.
@MainActor
final class ChimePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [AlarmSound: AVAudioPCMBuffer] = [:]
    private var ringTimer: Timer?
    private var configObserver: NSObjectProtocol?

    /// One unified rhythm for every sound: ring, wait 2s, ring, wait 2s, ring…
    private static let ringInterval: TimeInterval = 2.0
    private static let ringsWhenNotRepeating = 3
    private var ringsLeft = 0
    private var alarmSound: AlarmSound = .synthBell
    private var alarmVolume: Double = 0.7

    // All voices render at this fixed mono format; the player connection uses it
    // too, so a buffer never mismatches the graph (that mismatch = silent alarm).
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: ChimePlayer.format)
        engine.prepare()
        // AVAudioEngine stops itself on output-route / sample-rate changes
        // (headphones, dock, device switch). Reconnect so the next alarm restarts.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.engine.connect(self.player, to: self.engine.mainMixerNode, format: ChimePlayer.format)
            }
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Fire the alarm for a finished timer. Same rhythm for every sound: one ring
    /// now, then another every 2s — 3 times if not repeating, or until Dismiss.
    func playAlarm(sound: AlarmSound, volume: Double, repeatUntilDismissed: Bool) {
        stop()
        alarmSound = sound
        alarmVolume = volume
        ringsLeft = repeatUntilDismissed ? Int.max : ChimePlayer.ringsWhenNotRepeating
        fireRing()   // ring #1 immediately
        let t = Timer(timeInterval: ChimePlayer.ringInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fireRing() }
        }
        RunLoop.main.add(t, forMode: .common)
        ringTimer = t
    }

    /// A short audition for the settings panel — one motif, no repeats.
    func preview(sound: AlarmSound, volume: Double) {
        stop()
        play(sound: sound, volume: volume)
    }

    /// Stop any ongoing/repeating alarm (called on Dismiss).
    func stop() {
        ringTimer?.invalidate()
        ringTimer = nil
        ringsLeft = 0
        if player.isPlaying { player.stop() }
    }

    // MARK: - Private

    private func fireRing() {
        guard ringsLeft > 0 else {
            ringTimer?.invalidate(); ringTimer = nil; return
        }
        ringsLeft -= 1
        play(sound: alarmSound, volume: alarmVolume)
        if ringsLeft == 0 { ringTimer?.invalidate(); ringTimer = nil }
    }

    private func buffer(for sound: AlarmSound) -> AVAudioPCMBuffer? {
        if let cached = buffers[sound] { return cached }
        let made = BellSynth.makeBuffer(for: sound)
        if let made { buffers[sound] = made }
        return made
    }

    /// Play one motif of the sound.
    private func play(sound: AlarmSound, volume: Double) {
        guard let buffer = buffer(for: sound) else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        engine.mainMixerNode.outputVolume = Float(min(max(volume, 0), 1))
        if player.isPlaying { player.stop() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }
}
