import Foundation

/// Picks how often `TimerDial` should redraw while a timer runs.
///
/// Smoothness is not about the frame count — it's about how far the ring travels
/// BETWEEN frames. The ring advances by *distance*, so a short timer sweeps it far
/// faster than a long one: on a 222 pt dial (≈697 pt of circumference) a 1-minute
/// session moves it 11.6 pt per second while a 25-minute session moves it 0.46 — a
/// 25x difference in what the eye is actually given. Asking for 30 fps everywhere
/// spent the same effort on both; asking for 2 fps everywhere made short timers
/// visibly step (owner confirmed it on 44-second and 1-minute timers).
///
/// So the rule is one line: keep each step under half a point. That produces the
/// whole ladder — ~30 fps under 2 minutes, 12 fps to 4, 6 fps to 12, then 2 fps —
/// and it stays correct when the dial is resized, which a hardcoded rate could not.
///
/// **Why the slow end is worth having.** On an M1 Max with the window on a Retina
/// display, 30 fps measured 11.25% of a CPU core against 2.38% at 2 fps, over a
/// 1.40% floor with no dial redraws at all (that floor is the 1 Hz menu-bar label
/// plus the engine's ticker, neither of which this controls). `sample` puts the cost
/// in the display cycle: every update triggers a full NSWindow layout pass.
///
/// **Why the fast end is affordable.** Power is rate x TIME. A 1-minute timer at
/// 30 fps spends ~6.8 CPU-seconds in total; a 25-minute timer at 2 fps spends ~35.7.
/// The long sessions are what drain a battery, and those stay slow.
///
/// **Caveat on those numbers.** One machine, one display, one session. Cost per
/// update scales with the window's pixel count, so the same rate measured roughly
/// half as expensive with the window moved to a non-Retina screen, and individual
/// mid-ladder readings were too noisy to rank against each other. What isn't in
/// doubt is the arithmetic: 6 fps does exactly a fifth of the redraws of 30 fps.
enum DialFrameRate {
    /// A small closed set on purpose. A continuous formula tried here once asked for
    /// ~4 fps and cost more than twice what its own arithmetic predicted, so the dial
    /// only ever picks a value a human has looked at. Ascending.
    static let rates: [Double] = [2, 6, 12, 30]

    /// How far the ring may move between frames before the motion stops reading as
    /// continuous. Half a point is one physical pixel on a Retina display.
    static let maxStepPoints = 0.5

    /// The lowest rate in `rates` that keeps the ring's per-frame step within
    /// `maxStepPoints` — or the highest rate available when even that isn't enough
    /// (a very short timer, where 30 fps is still the best on offer).
    static func interval(dialDiameter: Double, duration: TimeInterval) -> Double {
        1 / rate(dialDiameter: dialDiameter, duration: duration)
    }

    static func rate(dialDiameter: Double, duration: TimeInterval) -> Double {
        let circumference = Double.pi * max(1, dialDiameter)
        let pointsPerSecond = circumference / max(1, duration)
        let needed = pointsPerSecond / maxStepPoints
        return rates.first { $0 >= needed } ?? rates.last!
    }
}
