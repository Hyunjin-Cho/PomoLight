import AVFoundation
import AppKit

/// Plays the gentle alarm. The default is our synthesized soft bell (two soft
/// "ding…ding" strikes); the alternatives are calm macOS system sounds. Also
/// supports "repeat until dismissed" by gently re-chiming on an interval.
@MainActor
final class ChimePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var bellBuffer: AVAudioPCMBuffer?
    private var systemSound: NSSound?
    private var repeatTimer: Timer?
    private var configObserver: NSObjectProtocol?

    init() {
        // Build the buffer FIRST, then connect the player using the buffer's exact
        // format. Connecting with `nil` lets the mixer pick a different format
        // (e.g. stereo @ the device's 48 kHz), and scheduling our mono 44.1 kHz
        // buffer into that mismatched connection plays SILENCE — that was the bug.
        bellBuffer = BellSynth.makeAlarmBuffer()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: bellBuffer?.format)
        engine.prepare()
        // AVAudioEngine stops itself on output-route / sample-rate changes
        // (headphones, dock, device switch). Reconnect so the next alarm restarts.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.engine.connect(self.player, to: self.engine.mainMixerNode, format: self.bellBuffer?.format)
            }
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Fire the alarm for a finished timer.
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

    /// A short audition for the settings panel — always a single strike.
    func preview(sound: AlarmSound, volume: Double) {
        stop()
        playOnce(sound: sound, volume: volume, strikes: 1)
    }

    /// Stop any ongoing/repeating alarm (called on Dismiss).
    func stop() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        if player.isPlaying { player.stop() }
        systemSound?.stop()
        systemSound = nil
    }

    // MARK: - Private

    private func playOnce(sound: AlarmSound, volume: Double, strikes: Int) {
        let vol = min(max(volume, 0), 1)
        if sound == .synthBell {
            playBell(volume: vol, strikes: strikes)
        } else if let name = sound.systemSoundName, let ns = NSSound(named: name) {
            ns.volume = Float(vol)
            ns.play()
            systemSound = ns
        } else {
            playBell(volume: vol, strikes: strikes)   // fallback
        }
    }

    private func playBell(volume: Double, strikes: Int) {
        guard let buffer = bellBuffer else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        engine.mainMixerNode.outputVolume = Float(volume)
        if player.isPlaying { player.stop() }
        for _ in 0..<max(1, strikes) {
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
        player.play()
    }
}
