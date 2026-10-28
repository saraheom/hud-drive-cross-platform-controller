import Foundation

/// Cache response footprints must reflect the actual query radii, not a single
/// global assumption. Older persisted cache files had no radius field and
/// exclusively contained the original 400m speed-tag query.
enum CurrentNavCacheCoverage {
    static func effectiveRadius(_ radius: Double?) -> Double {
        guard let radius, radius.isFinite, radius >= 60, radius <= 1000 else { return 400 }
        return radius
    }
    static func contains(queryRadiusMeters: Double?, distanceMeters: Double,
                         edgeMarginMeters: Double = 15) -> Bool {
        distanceMeters.isFinite && distanceMeters >= 0 &&
        distanceMeters <= effectiveRadius(queryRadiusMeters) - edgeMarginMeters
    }
    static func mergedRadius(incomingRadiusMeters: Double,
                             priorRadii: [Double?]) -> Double {
        ([effectiveRadius(incomingRadiusMeters)] + priorRadii.map(effectiveRadius)).max() ?? 400
    }
}
