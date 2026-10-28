import Foundation

/// Small targeted Overpass audit, independent from the live speed-tagged query.
/// The audit must NOT turn an HTTP failure or an empty search into an assumed speed.
enum CurrentNavOSMQuery {
    static func auditSearchToken(_ roadName: String) -> String? {
        let normalized = CurrentNavRoadIdentity.normalizedRoadPhrase(roadName)
        let stopWords: Set<String> = [
            "north", "south", "east", "west", "northbound", "southbound",
            "eastbound", "westbound", "street", "avenue", "road", "drive",
            "boulevard", "parkway", "lane", "court", "place", "terrace",
            "highway", "route", "state", "county", "junior", "the",
            "us", "pa", "sr", "i"
        ]
        let tokens = normalized.split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) &&
                $0.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) } }
        // Use the longest specific token to keep the Overpass result small while
        // retaining name variants (Ridge Ave vs Ridge Avenue, MLK vs Martin...).
        // For MLK choose 'luther' rather than the more ambiguous 'martin'.
        if normalized.contains("martin luther king") { return "luther" }
        return tokens.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }.first
    }

    static func namedRoadAudit(roadName: String, latitude: Double, longitude: Double,
                               radiusMeters: Int) -> String? {
        guard latitude.isFinite, longitude.isFinite,
              abs(latitude) <= 90, abs(longitude) <= 180,
              (60...450).contains(radiusMeters),
              let token = auditSearchToken(roadName) else { return nil }
        // Overpass QL supports POSIX case-insensitive tag regex with ,i.
        // This is narrower than requesting every [name] AND [ref] way in 170m.
        // A successful empty response only proves no result for this token in
        // this region, not absence of a legal speed limit on all of the road.
        let lat = String(format: "%.7f", latitude)
        let lon = String(format: "%.7f", longitude)
        return "[out:json][timeout:50];way[highway][name~\"\(token)\",i](around:\(radiusMeters),\(lat),\(lon));out tags geom;"
    }
}
