import Foundation

/// Geographic prefetch policy, independent of CoreLocation/SwiftUI. Used ONLY
/// by Current + Nav. Its centers are REAL Overpass query positions, never
/// fabricated road geometry or inferred posted-speed evidence.
enum CurrentNavCoveragePlanner {
    struct Point {
        let latitude: Double
        let longitude: Double
    }

    static let aheadMeters = 270.0

    static func fetchCenter(latitude: Double, longitude: Double,
                            courseDegrees: Double, speedMetersPerSecond: Double) -> Point {
        guard latitude.isFinite, longitude.isFinite,
              courseDegrees.isFinite, courseDegrees >= 0 && courseDegrees < 360,
              speedMetersPerSecond.isFinite, speedMetersPerSecond >= 2.5 else {
            return Point(latitude: latitude, longitude: longitude)
        }
        let heading = courseDegrees * .pi / 180
        let deltaLat = aheadMeters * cos(heading) / 111_132.0
        let metersPerLongitude = 111_320.0 * cos(latitude * .pi / 180)
        guard abs(metersPerLongitude) > 10 else {
            return Point(latitude: latitude, longitude: longitude)
        }
        let deltaLon = aheadMeters * sin(heading) / metersPerLongitude
        return Point(latitude: latitude + deltaLat, longitude: longitude + deltaLon)
    }

    static func distanceMeters(_ first: Point, _ second: Point) -> Double {
        let meanLatitude = (first.latitude + second.latitude) / 2
        let north = (first.latitude - second.latitude) * 111_132.0
        let east = (first.longitude - second.longitude) *
            111_320.0 * cos(meanLatitude * .pi / 180)
        return hypot(north, east)
    }

    static func nearestCenterDistanceMeters(point: Point, centers: [Point]) -> Double {
        centers.map { distanceMeters(point, $0) }.min() ?? .infinity
    }
}
