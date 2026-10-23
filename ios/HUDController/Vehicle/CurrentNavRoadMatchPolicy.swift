import Foundation

/// Isolated, platform-independent geometry policy used ONLY by Current + Nav.
/// Keeping this small permits deterministic testing on Linux without CoreLocation.
/// The legacy Current matcher deliberately does not use this policy.
enum CurrentNavRoadMatchPolicy {
    static let maximumCorridorMeters = 34.0
    static let maximumMovingHeadingErrorDegrees = 65.0

    /// True perpendicular distance to a finite OSM polyline segment. The local
    /// equirectangular projection is appropriate for the <=430m Overpass slice.
    static func distanceToSegmentMeters(
        latitude: Double, longitude: Double,
        startLatitude: Double, startLongitude: Double,
        endLatitude: Double, endLongitude: Double
    ) -> Double {
        let metersPerLat = 111_132.0
        let metersPerLon = 111_320.0 * cos(latitude * .pi / 180)
        let ax = (startLongitude - longitude) * metersPerLon
        let ay = (startLatitude - latitude) * metersPerLat
        let bx = (endLongitude - longitude) * metersPerLon
        let by = (endLatitude - latitude) * metersPerLat
        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-9 else { return hypot(ax, ay) }
        let t = max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
        return hypot(ax + t * dx, ay + t * dy)
    }

    /// The road NAME must match first. A motorway 5m away cannot override a
    /// confirmed different CarPlay street even if its GPS score is excellent.
    /// Heading is not required near stationary speed where GPS course is noisy.
    static func eligible(
        semanticRoadNameMatch: Bool,
        distanceMeters: Double,
        gpsAccuracyMeters: Double,
        moving: Bool,
        headingErrorDegrees: Double
    ) -> Bool {
        guard semanticRoadNameMatch, distanceMeters.isFinite, distanceMeters >= 0 else { return false }
        let corridor = min(maximumCorridorMeters, max(20.0, max(0, gpsAccuracyMeters) * 1.4))
        return distanceMeters <= corridor &&
            (!moving || (headingErrorDegrees >= 0 && headingErrorDegrees <= maximumMovingHeadingErrorDegrees))
    }
}
