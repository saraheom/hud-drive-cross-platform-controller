import Foundation

/// Prevents GPS jitter from switching between simultaneously plausible, differently
/// tagged OSM ways on the same CarPlay road. This never creates a speed limit.
/// Route changes, missing previous geometry, or an unambiguous new way bypass it.
enum CurrentNavSpeedSwitchPolicy {
    static let requiredConsecutiveObservations = 3

    static func needsConfirmation(
        previousWayID: Int64, proposedWayID: Int64,
        previousKmh: Int?, proposedKmh: Int?,
        previousDistanceMeters: Double, proposedDistanceMeters: Double,
        previousHeadingErrorDegrees: Double, proposedHeadingErrorDegrees: Double
    ) -> Bool {
        guard previousWayID != proposedWayID,
              let previousKmh, let proposedKmh, previousKmh != proposedKmh,
              previousDistanceMeters.isFinite, proposedDistanceMeters.isFinite,
              previousHeadingErrorDegrees.isFinite, proposedHeadingErrorDegrees.isFinite else { return false }
        // Only a previously verified, still geometrically credible same-road way
        // can hold its display briefly. Beyond this corridor, accept the new tag.
        return previousDistanceMeters <= 24.0 &&
               previousDistanceMeters <= proposedDistanceMeters + 10.0 &&
               previousHeadingErrorDegrees <= min(82.0, proposedHeadingErrorDegrees + 25.0)
    }
}
