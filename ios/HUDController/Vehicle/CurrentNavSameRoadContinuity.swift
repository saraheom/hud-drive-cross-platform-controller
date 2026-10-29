import Foundation

/// Display-only continuity for *previously observed, explicitly tagged* OSM
/// speed limits. A CarPlay street-name match alone can never establish a speed;
/// a fresh GPS-to-same-road geometry match must accompany each carried sample.
///
/// The anchor's original verification time and the cumulative travel distance
/// never reset on a carry. In particular, an untagged road cannot extend the
/// validity of an earlier posted limit indefinitely. Overspeed warnings must
/// NEVER be enabled from this policy's result.
enum CurrentNavSameRoadContinuity {
    static let maximumAgeSeconds: TimeInterval = 12 * 60
    static let maximumTravelMeters: Double = 6_000

    struct Anchor {
        let identity: String
        let speedMph: Int
        let explicitlyVerifiedAt: Date
        let lastLatitude: Double
        let lastLongitude: Double
        let lastConfirmedAt: Date
        let travelledMeters: Double
    }

    static func verified(identity: String, speedMph: Int,
                         latitude: Double, longitude: Double, now: Date) -> Anchor? {
        guard !identity.isEmpty, (5...100).contains(speedMph),
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return Anchor(identity: identity, speedMph: speedMph,
                      explicitlyVerifiedAt: now, lastLatitude: latitude,
                      lastLongitude: longitude, lastConfirmedAt: now,
                      travelledMeters: 0)
    }

    static func distanceMeters(latitudeA: Double, longitudeA: Double,
                               latitudeB: Double, longitudeB: Double) -> Double {
        let r = Double.pi / 180.0
        let dLat = (latitudeB - latitudeA) * r
        let dLon = (longitudeB - longitudeA) * r
        let a = pow(sin(dLat / 2), 2) +
            cos(latitudeA * r) * cos(latitudeB * r) * pow(sin(dLon / 2), 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(max(0, a))))
    }

    /// Returns a new state only if the road is still *independently* confirmed.
    /// If no road geometry matched, the caller may use the original 12-second
    /// GPS-gap hold; never extend this longer continuity through missing maps.
    static func advance(_ anchor: Anchor?, roadIdentity: String,
                        latitude: Double, longitude: Double, now: Date,
                        matchedSameRoadGeometry: Bool,
                        contradictoryPostedLimitNearby: Bool) -> Anchor? {
        guard let anchor, anchor.identity == roadIdentity,
              matchedSameRoadGeometry, !contradictoryPostedLimitNearby,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let age = now.timeIntervalSince(anchor.explicitlyVerifiedAt)
        let elapsed = now.timeIntervalSince(anchor.lastConfirmedAt)
        guard age >= 0, age <= maximumAgeSeconds,
              elapsed >= 0 else { return nil }
        let step = distanceMeters(latitudeA: anchor.lastLatitude,
                                  longitudeA: anchor.lastLongitude,
                                  latitudeB: latitude, longitudeB: longitude)
        // Reject sudden jumps in a recycled street name or gross GPS outliers.
        // A parked/low-speed GPS wobble below 3 m doesn't consume the allowance.
        if elapsed <= 15 && step > max(120, elapsed * 65 + 70) { return nil }
        let travelled = anchor.travelledMeters + (step < 3 ? 0 : step)
        guard travelled <= maximumTravelMeters else { return nil }
        return Anchor(identity: anchor.identity, speedMph: anchor.speedMph,
                      explicitlyVerifiedAt: anchor.explicitlyVerifiedAt,
                      lastLatitude: latitude, lastLongitude: longitude,
                      lastConfirmedAt: now, travelledMeters: travelled)
    }
}
