import Foundation

/// The production Current + Nav semantic road-identity policy. Kept
/// Foundation-only so logged CarPlay street transitions can be replayed
/// with mocked OSM responses on non-iOS CI hosts.
enum CurrentNavRoadIdentity {
    static func normalizedRoadPhrase(_ raw: String) -> String {
        let aliases: [String: String] = [
            "n": "north", "s": "south", "e": "east", "w": "west",
            "nb": "northbound", "sb": "southbound", "eb": "eastbound", "wb": "westbound",
            "mlk": "martin luther king", "jr": "junior", "dr": "drive", "rd": "road", "st": "street",
            "ave": "avenue", "av": "avenue", "blvd": "boulevard",
            "hwy": "highway", "pkwy": "parkway", "expy": "expressway",
            "expwy": "expressway", "expw": "expressway", "ln": "lane",
            "ct": "court", "pl": "place", "ter": "terrace"
        ]
        let normalized = raw
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { aliases[$0] ?? $0 }
            .joined(separator: " ")
        // Apple commonly reports "Martin Luther King Dr" while OSM in
        // Philadelphia uses "Martin Luther King Junior Drive". Canonicalize the
        // optional honorific so Route Guidance can reinforce the same physical road.
        return normalized.replacingOccurrences(
            of: "martin luther king junior ",
            with: "martin luther king "
        )
    }

    /// CarPlay may include a leading cardinal that the OSM name omits.
    /// Accept exactly one missing leading cardinal only; an explicit North/South
    /// or East/West disagreement is never a semantic match. Geometry, heading,
    /// and posted-tag confidence remain mandatory in the calling speed matcher.
    private static func omittedDirectionalPrefixMatches(_ left: String, _ right: String) -> Bool {
        let directions: Set<String> = ["north", "south", "east", "west"]
        let a = left.split(separator: " ").map(String.init)
        let b = right.split(separator: " ").map(String.init)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if directions.contains(a[0]), !directions.contains(b[0]) {
            return Array(a.dropFirst()) == b
        }
        if directions.contains(b[0]), !directions.contains(a[0]) {
            return Array(b.dropFirst()) == a
        }
        return false
    }

    static func routeRoadMatches(_ rawRouteRoad: String, name: String?, reference: String?) -> Bool {
        let route = normalizedRoadPhrase(rawRouteRoad)
        guard !route.isEmpty else { return false }
        if let name {
            let candidate = normalizedRoadPhrase(name)
            if !candidate.isEmpty, candidate == route { return true }
            if omittedDirectionalPrefixMatches(route, candidate) { return true }
        }
        if let reference {
            let ref = normalizedRoadPhrase(reference)
            if !ref.isEmpty {
                if route == ref { return true }
                // Route Guidance sometimes adds a cardinal suffix to a highway ref
                // (e.g. "US 1 North") while OSM stores only ref="US 1".
                if route.hasPrefix(ref + " ") || route.hasSuffix(" " + ref) { return true }
            }
        }
        return false
    }
}
