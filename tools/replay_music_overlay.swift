import Foundation

func assertNear(_ actual: Double, _ expected: Double, _ tolerance: Double = 0.00001) {
    precondition(abs(actual - expected) < tolerance, "expected \(expected) got \(actual)")
}

@main struct Test {
static func main() {
    // Playback only: no stale/paused or blank media.
    precondition(HudMapMusicBehavior.isVisible(polling: true, reachable: true, playing: true, title: "Song", ageSeconds: 0.8))
    for playing in [false] {
        precondition(!HudMapMusicBehavior.isVisible(polling: true, reachable: true, playing: playing, title: "Song", ageSeconds: 0.8))
    }
    precondition(!HudMapMusicBehavior.isVisible(polling: true, reachable: false, playing: true, title: "Song", ageSeconds: 0.8))
    precondition(!HudMapMusicBehavior.isVisible(polling: true, reachable: true, playing: true, title: "No CarPlay media", ageSeconds: 0.8))
    precondition(!HudMapMusicBehavior.isVisible(polling: true, reachable: true, playing: true, title: "Song", ageSeconds: 5.1))
    precondition(!HudMapMusicBehavior.isVisible(polling: true, reachable: true, playing: true, title: " ", ageSeconds: 0.8))

    // Progress never exceeds track duration, starts fresh on a new track.
    precondition(HudMapMusicBehavior.interpolatedElapsedMs(60_000, durationMs: 180_000, ageSeconds: 0.75) == 60_750)
    precondition(HudMapMusicBehavior.interpolatedElapsedMs(179_800, durationMs: 180_000, ageSeconds: 0.75) == 180_000)
    precondition(HudMapMusicBehavior.interpolatedElapsedMs(0, durationMs: 180_000, ageSeconds: 0.0) == 0)

    // A short title never moves; an overlong title moves smoothly at 24px/s,
    // pauses at each end, then returns with no abrupt jump.
    assertNear(HudMapMusicBehavior.marqueeOffset(contentWidth: 70, viewportWidth: 150, trackAgeSeconds: 2, pixelsPerSecond: 24), 0)
    assertNear(HudMapMusicBehavior.marqueeOffset(contentWidth: 200, viewportWidth: 100, trackAgeSeconds: 1.5, pixelsPerSecond: 24), 0)
    assertNear(HudMapMusicBehavior.marqueeOffset(contentWidth: 200, viewportWidth: 100, trackAgeSeconds: 2.5, pixelsPerSecond: 24), -24)
    let travel = 100.0 / 24
    assertNear(HudMapMusicBehavior.marqueeOffset(contentWidth: 200, viewportWidth: 100, trackAgeSeconds: 1.5+travel, pixelsPerSecond: 24), -100)
    assertNear(HudMapMusicBehavior.marqueeOffset(contentWidth: 200, viewportWidth: 100, trackAgeSeconds: 3+travel, pixelsPerSecond: 24), -100)
    assertNear(HudMapMusicBehavior.marqueeOffset(contentWidth: 200, viewportWidth: 100, trackAgeSeconds: 3+2*travel, pixelsPerSecond: 24), 0)
    print("PASS: 13 native Swift music playback, timing and scrolling assertions")
}
}
