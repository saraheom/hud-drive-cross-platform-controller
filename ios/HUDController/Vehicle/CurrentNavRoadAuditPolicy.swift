import Foundation

/// Interprets the result of an actual HTTP Overpass named-road response.
/// A speed-tag-filtered response alone cannot prove a speed tag is missing:
/// that query excludes untagged OSM ways. Classification never supplies a limit.
enum CurrentNavRoadAuditPolicy {
    static func classification(httpSucceeded: Bool,
                               namedRoadCount: Int,
                               nearbyNamedRoadCount: Int,
                               explicitlyTaggedNearbyCount: Int) -> String {
        guard httpSucceeded else { return "REQUEST_FAILED_INDETERMINATE" }
        guard namedRoadCount > 0 else { return "ROAD_NAME_NOT_RETURNED_IN_LOCAL_QUERY" }
        guard nearbyNamedRoadCount > 0 else { return "ROAD_NAME_PRESENT_BUT_GEOMETRY_OUTSIDE_CORRIDOR" }
        guard explicitlyTaggedNearbyCount > 0 else { return "NEARBY_NAMED_WAY_NO_SUPPORTED_SPEED_TAG" }
        return "NEARBY_NAMED_WAY_HAS_EXPLICIT_SPEED_TAG"
    }
}
