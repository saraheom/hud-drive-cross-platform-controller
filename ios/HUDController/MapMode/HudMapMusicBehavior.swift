import Foundation

/// Pure, frame-rate-independent Now Playing presentation rules. Neither Apple
/// Maps nor Google Maps route metadata is required for media presentation.
enum HudMapMusicBehavior {
    static func isVisible(
        polling: Bool,
        reachable: Bool,
        playing: Bool,
        title: String,
        ageSeconds: Double
    ) -> Bool {
        polling && reachable && playing &&
        ageSeconds.isFinite && ageSeconds >= 0 && ageSeconds < 5 &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        title != "No CarPlay media"
    }

    static func interpolatedElapsedMs(_ elapsedMs: Int, durationMs: Int, ageSeconds: Double) -> Int {
        guard ageSeconds.isFinite, ageSeconds >= 0 else { return 0 }
        let seconds = min(5.0, ageSeconds)
        let base = max(0, elapsedMs)
        let interpolated = base + Int(seconds * 1000)
        return durationMs > 0 ? min(durationMs, interpolated) : interpolated
    }

    /// One traversal, opposite traversal and a 1.5 s dwell at each edge.
    /// The motion is tied to track age rather than the output frame counter.
    static func marqueeOffset(
        contentWidth: Double,
        viewportWidth: Double,
        trackAgeSeconds: Double,
        pixelsPerSecond: Double
    ) -> Double {
        let overflow = max(0, contentWidth - viewportWidth)
        guard overflow > 1, trackAgeSeconds.isFinite, trackAgeSeconds >= 0 else { return 0 }
        let rate = max(8, min(60, pixelsPerSecond))
        let travel = overflow / rate
        let pause = 1.5
        let period = pause * 2 + travel * 2
        let time = trackAgeSeconds.truncatingRemainder(dividingBy: period)
        if time < pause { return 0 }
        if time < pause + travel { return -(time - pause) * rate }
        if time < pause + travel + pause { return -overflow }
        return -max(0, overflow - (time - 2 * pause - travel) * rate)
    }
}
