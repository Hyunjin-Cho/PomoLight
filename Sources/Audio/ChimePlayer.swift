import AVFoundation
import os

/// Plays the gentle alarm. Every sound is synthesized in-app (one short motif per
/// ring); "repeat until dismissed" re-chimes on an interval until Dismiss.
///
/// The audio engine is only ever ON while something is sounding. See
/// `graph()` for when it is built and `stopEngineIfIdle()` for when it is switched
/// off again — both are deliberate, and both were measured.
@MainActor
final class ChimePlayer {
    // 2026-11-15 (#60): these two used to be `let` properties, constructed when the
    // app launched. Constructing them touches no hardware, but a session that never
    // rings has no use for them, so they are now created together with the graph,
    // the first time a sound is about to play.
    //
    // Do not read this as a memory win that was proven in the app. In a bare
    // process the two objects cost 1.5 MB of footprint (1.64 → 3.14 MB); in the real
    // app the launch footprint swings by ±3 MB from one run to the next (33.8–37.5
    // before, 32.0–39.1 after, three runs each) and the live heap did not move
    // (15.3–15.4 MB vs 15.2–15.3 MB), so the difference could not be resolved.
    // The app sits about 6 MB above an empty SwiftUI app of the same shape
    // (31.4 MB); there is little left here to take.
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffers: [AlarmSound: AVAudioPCMBuffer] = [:]
    private var ringTimer: Timer?
    private var idleTimer: Timer?
    private var configObserver: NSObjectProtocol?

    /// One unified rhythm for every sound: ring, wait 2s, ring, wait 2s, ring…
    private static let ringInterval: TimeInterval = 2.0
    private static let ringsWhenNotRepeating = 3
    private var ringsLeft = 0
    private var alarmSound: AlarmSound = .marimba
    private var alarmVolume: Double = 0.7

    /// How long after the last sound has rung out the engine is switched off. Long
    /// enough that auditioning one voice after another in the settings panel does
    /// not stop and restart the output between clicks; short enough to be over
    /// before anyone could notice.
    private static let idleGrace: TimeInterval = 0.5

    // All voices render at this fixed mono format; the player connection uses it
    // too, so a buffer never mismatches the graph (that mismatch = silent alarm).
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)

    init() {
        // 🚨 2026-08-20: nothing audio-related may happen here. The graph used to be
        // built in `init`, and that made launching the app audible: touching
        // `engine.mainMixerNode` is what makes CoreAudio go and open the default
        // output device, and on the owner's Mac Studio the speakers answer that with
        // a single "tick". PomoLight therefore clicked every single launch, whether
        // or not a timer was ever started. The unified log shows it plainly: AUHAL
        // SelectDevice and a DefaultDeviceAggregate get built about 150 ms BEFORE
        // applicationDidFinishLaunching, with no matching start/stop pair anywhere,
        // because nothing was ever played. `Scripts/silent_launch_check.sh` guards it.
    }

    /// The render graph, built on first use. Building it opens the audio device as
    /// a side effect, so this is called at the moment a sound is actually about to
    /// play: the device-open click lands underneath the chime that follows it
    /// instead of arriving out of nowhere.
    ///
    /// Once built, the graph is KEPT for the rest of the session — it is the engine
    /// that gets switched off between alarms, not the graph that gets torn down.
    /// 2026-11-15 (#60), measured: stopping and restarting the engine does not
    /// select the device again (the log shows a `setPlayState Stopped/Started` pair
    /// and no new `Selecting device`), whereas discarding the engine and building a
    /// new one does — that would move the click to every alarm. Discarding it also
    /// gave no memory back (5.92 → 5.94 MB), so there is nothing to gain from it.
    private func graph() -> (engine: AVAudioEngine, player: AVAudioPlayerNode) {
        if let engine, let player { return (engine, player) }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: ChimePlayer.format)
        engine.prepare()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // The observer only exists once the graph does, so there is always
                // something to reconnect here — a route change can no longer open
                // the device on behalf of an app that never played anything.
                guard let self, let engine = self.engine, let player = self.player else { return }
                engine.connect(player, to: engine.mainMixerNode, format: ChimePlayer.format)
            }
        }
        self.engine = engine
        self.player = player
        return (engine, player)
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

    /// Stop any ongoing/repeating alarm (called on Dismiss and Reset).
    func stop() {
        ringTimer?.invalidate()
        ringTimer = nil
        ringsLeft = 0
        // Never played anything: there is no engine, and nothing here may create one.
        guard let engine, let player else { return }
        if player.isPlaying { player.stop() }
        // Not stopped on the spot: `preview` calls this and plays again in the same
        // breath, and that must not bounce the output off and on.
        if engine.isRunning { scheduleEngineStop(after: ChimePlayer.idleGrace) }
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

    // 2026-08-21: both failure paths in `play` used to return in silence. This app
    // IS an alarm, so "it didn't ring" with no trace anywhere is the one bug report
    // nobody can act on. `Scripts/silent_launch_check.sh` already reads the unified
    // log, so a failure recorded here is reachable by the existing verification.
    private static let log = Logger(subsystem: "com.vismo.pomolight", category: "chime")

    /// Play one motif of the sound.
    private func play(sound: AlarmSound, volume: Double) {
        // Resolve the buffer BEFORE the graph: a voice we cannot synthesize must not
        // be the reason the audio device gets opened.
        guard let buffer = buffer(for: sound) else {
            ChimePlayer.log.error("alarm did not ring: could not synthesize \(sound.rawValue, privacy: .public)")
            return
        }
        let (engine, player) = graph()
        cancelEngineStop()
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                ChimePlayer.log.error("alarm did not ring: audio engine failed to start — \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        engine.mainMixerNode.outputVolume = Float(min(max(volume, 0), 1))
        if player.isPlaying { player.stop() }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
        // No ring left to come — a preview, or the last ring of an alarm that does
        // not repeat. Once this motif has rung out, the engine can go off. While more
        // rings are due it stays on: stopping in the gaps would restart the output
        // every two seconds for as long as the alarm rang.
        if ringsLeft == 0 {
            let length = Double(buffer.frameLength) / buffer.format.sampleRate
            scheduleEngineStop(after: length + ChimePlayer.idleGrace)
        }
    }

    // MARK: - Switching the engine off

    // 🚨 2026-11-15 (#60): the engine used to be started once and never stopped —
    // `stop()` silenced the player node and left the engine running "for the rest
    // of the session". A running engine is a running output, sound or no sound, and
    // macOS answers that with a sleep assertion held on the app's behalf. Measured
    // on the shipping build: nothing before the first alarm, then
    //
    //     pid 790(coreaudiod) PreventUserIdleSystemSleep … Created for PID: <us>
    //
    // from the first ring onwards, still there a minute and a half after Dismiss.
    // So one alarm — or one preview in the settings panel — kept the Mac from
    // sleeping on its own until PomoLight was quit, with "Keep Mac awake" OFF and
    // no timer running. It also cost an idle 0.36% of a core that drops to 0.00%.
    // `engine.stop()` releases the assertion at once (same measurement).

    private func scheduleEngineStop(after delay: TimeInterval) {
        idleTimer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopEngineIfIdle() }
        }
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    private func cancelEngineStop() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func stopEngineIfIdle() {
        idleTimer = nil
        // A ring that is still due means the alarm is live — leave the output alone.
        guard ringsLeft == 0, ringTimer == nil, let engine, engine.isRunning else { return }
        player?.stop()
        engine.stop()
    }
}
