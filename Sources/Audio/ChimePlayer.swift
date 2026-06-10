import AVFoundation

/// Plays the gentle alarm. Every sound is synthesized in-app (a short motif played
/// twice); "repeat until dismissed" re-chimes on an interval until Dismiss.
@MainActor
final class ChimePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [AlarmSound: AVAudioPCMBuffer] = [:]
    private var repeatTimer: Timer?
    private var configObserver: NSObjectProtocol?

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

    /// Fire the alarm for a finished timer (motif played twice, optionally repeating).
    func playAlarm(sound: AlarmSound, volume: Double, repeatUntilDismissed: Bool) {
        stop()
        playOnce(sound: sound, volume: volume, strikes: 2)
        if repeatUntilDismissed {
            let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.playOnce(sound: sound, volume: volume, strikes: 2) }
            }
            RunLoop.main.add(t, forMode: .common)
            repeatTimer = t
        }
    }

    /// A short audition for the settings panel — one motif.
    func preview(sound: AlarmSound, volume: Double) {
        stop()
        playOnce(sound: sound, volume: volume, strikes: 1)
    }

    /// Stop any ongoing/repeating alarm (called on Dismiss).
    func stop() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        if player.isPlaying { player.stop() }
    }

    // MARK: - Private

    private func buffer(for sound: AlarmSound) -> AVAudioPCMBuffer? {
        if let cached = buffers[sound] { return cached }
        let made = BellSynth.makeBuffer(for: sound)
        if let made { buffers[sound] = made }
        return made
    }

    private func playOnce(sound: AlarmSound, volume: Double, strikes: Int) {
        guard let buffer = buffer(for: sound) else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        engine.mainMixerNode.outputVolume = Float(min(max(volume, 0), 1))
        if player.isPlaying { player.stop() }
        for _ in 0..<max(1, strikes) {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
        player.play()
    }
}
