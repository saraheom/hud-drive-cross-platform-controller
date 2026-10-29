import Foundation

/// Read-only, spatially indexed snapshot of OSM-derived Philadelphia roads.
/// The packaged dataset is generated from the public OSM Roads Philadelphia
/// ArcGIS layer at build time. It cannot create missing posted-speed tags.
struct CurrentNavOfflineOSMIndex {
    struct Road: Codable {
        let id: Int64
        let highway: String
        let name: String?
        let reference: String?
        let maxspeedKmh: Int?
        /// Each pair is [latitude, longitude] in WGS84.
        let coordinates: [[Double]]
    }

    struct Payload: Codable {
        let version: Int
        let source: String
        let generatedAt: String
        let roads: [Road]
    }

    private let roads: [Road]
    private let cells: [String: [Int]]
    private static let cellDegrees = 0.004

    static func cellKey(latitude: Double, longitude: Double) -> String {
        let y = Int(floor(latitude / cellDegrees))
        let x = Int(floor(longitude / cellDegrees))
        return "\(y):\(x)"
    }

    static func load(data: Data) throws -> CurrentNavOfflineOSMIndex {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.version == 1, payload.source.lowercased().contains("osm") else {
            throw NSError(domain: "CurrentNavOfflineOSMIndex", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid OSM bundle provenance/version"])
        }
        // An empty placeholder is intentionally NOT a valid offline map.
        guard !payload.roads.isEmpty else {
            throw NSError(domain: "CurrentNavOfflineOSMIndex", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Offline OSM bundle is empty"])
        }
        let supported: Set<String> = ["motorway", "motorway_link", "trunk", "trunk_link",
            "primary", "primary_link", "secondary", "secondary_link", "tertiary",
            "tertiary_link", "unclassified", "residential", "living_street", "service", "road"]
        var accepted: [Road] = []
        var grid: [String: [Int]] = [:]
        for road in payload.roads {
            guard supported.contains(road.highway), road.coordinates.count >= 2,
                  road.coordinates.count <= 10000,
                  road.coordinates.allSatisfy({ $0.count == 2 && $0[0].isFinite && $0[1].isFinite &&
                      (39.7...40.3).contains($0[0]) && (-75.6 ... -74.8).contains($0[1]) }),
                  road.maxspeedKmh.map({ (8...160).contains($0) }) ?? true else { continue }
            let minLat = road.coordinates.map { $0[0] }.min()!
            let maxLat = road.coordinates.map { $0[0] }.max()!
            let minLon = road.coordinates.map { $0[1] }.min()!
            let maxLon = road.coordinates.map { $0[1] }.max()!
            let y0 = Int(floor(minLat / cellDegrees)); let y1 = Int(floor(maxLat / cellDegrees))
            let x0 = Int(floor(minLon / cellDegrees)); let x1 = Int(floor(maxLon / cellDegrees))
            // Malformed huge outlines never populate millions of grid buckets.
            guard (y1-y0+1) * (x1-x0+1) <= 128 else { continue }
            let index = accepted.count
            accepted.append(road)
            for y in y0...y1 {
                for x in x0...x1 { grid["\(y):\(x)", default: []].append(index) }
            }
        }
        return CurrentNavOfflineOSMIndex(roads: accepted, cells: grid)
    }

    var roadCount: Int { roads.count }
    var speedTaggedCount: Int { roads.filter { $0.maxspeedKmh != nil }.count }

    func nearby(latitude: Double, longitude: Double) -> [Road] {
        let cy = Int(floor(latitude / Self.cellDegrees))
        let cx = Int(floor(longitude / Self.cellDegrees))
        var indices: Set<Int> = []
        for y in (cy-1)...(cy+1) {
            for x in (cx-1)...(cx+1) {
                for id in cells["\(y):\(x)"] ?? [] { indices.insert(id) }
            }
        }
        return indices.sorted().map { roads[$0] }
    }
}
