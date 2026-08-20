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

    /// Whether the render graph has been built. See `prepareGraphIfNeeded`.
    private var graphReady = false

    init() {
        // 🚨 2026-08-20: the graph is NOT built here. It used to be, and that made
        // launching the app audible: touching `engine.mainMixerNode` is what makes
        // CoreAudio go and open the default output device, and on the owner's Mac
        // Studio the speakers answer that with a single "tick". PomoLight therefore
        // clicked every single launch, whether or not a timer was ever started —
        // and it then held the device open for the life of the process. The unified
        // log shows it plainly: AUHAL SelectDevice and a DefaultDeviceAggregate get
        // built about 150 ms BEFORE applicationDidFinishLaunching, with no matching
        // start/stop pair anywhere, because nothing was ever played.
        //
        // Constructing AVAudioEngine and AVAudioPlayerNode on their own touches no
        // hardware, so those stay. Only the wiring moves to first use.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Nothing to reconnect if we never connected — and doing it anyway
                // would re-open the device from a background route change, which is
                // the very click this deferral exists to avoid.
                guard let self, self.graphReady else { return }
                self.engine.connect(self.player, to: self.engine.mainMixerNode, format: ChimePlayer.format)
            }
        }
    }

    /// Build the render graph, opening the audio device as a side effect. Called at
    /// the moment a sound is actually about to play, so the device-open click lands
    /// underneath the chime that follows it instead of arriving out of nowhere. The
    /// device then stays open for the rest of the session: releasing it between
    /// alarms would just move the click to every ring instead of removing it.
    private func prepareGraphIfNeeded() {
        guard !graphReady else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: ChimePlayer.format)
        engine.prepare()
        graphReady = true
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
        if graphReady, player.isPlaying { player.stop() }
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
        // Resolve the buffer BEFORE the graph: a voice we cannot synthesize must not
        // be the reason the audio device gets opened.
        guard let buffer = buffer(for: sound) else { return }
        prepareGraphIfNeeded()
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        engine.mainMixerNode.outputVolume = Float(min(max(volume, 0), 1))
        if player.isPlaying { player.stop() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }
}
