import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class OriginalSpeedLimitEngine: NSObject, CLLocationManagerDelegate {
    struct Coordinate: Decodable {
        let lat: Double
        let lon: Double
    }

    struct Tags: Decodable {
        let highway: String?
        let maxspeed: String?
    }

    struct Element: Decodable {
        let type: String
        let id: Int64
        let geometry: [Coordinate]?
        let tags: Tags?
    }

    struct Response: Decodable {
        let elements: [Element]
    }

    struct Segment {
        let speedMph: Int
        let isMph: Bool
        let points: [CLLocationCoordinate2D]
    }

    private let locationManager = CLLocationManager()
    private let bluetooth: HudBluetoothManager
    private let logger: LogManager

    private var segments: [Segment] = []
    private var lastQueryLocation: CLLocation?
    private var requestInFlight = false
    private var lastSentSpeed = -1
    private var lastSentLimit = -1

    private(set) var currentSpeedMph = 0
    private(set) var currentSpeedLimitMph = 0
    private(set) var status = "Waiting for location"

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "HUD.Speed.enabled")
            if enabled { start() } else { stop() }
        }
    }

    var speedTolerance: Int {
        didSet {
            let clamped = max(0, min(30, speedTolerance))
            if clamped != speedTolerance {
                speedTolerance = clamped
                return
            }
            UserDefaults.standard.set(speedTolerance, forKey: "HUD.Speed.toleranceMph")
            // Force the currently displayed limit/warning to refresh.
            lastSentLimit = -1
            resendCurrentLimitIfPossible()
        }
    }

    var showSpeedLimit: Bool {
        didSet {
            UserDefaults.standard.set(showSpeedLimit, forKey: "HUD.Speed.showLimit")
            if showSpeedLimit && !enabled {
                enabled = true
            }
            lastSentLimit = -1
            resendCurrentLimitIfPossible()
        }
    }

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger

        let d = UserDefaults.standard
        self.enabled = d.object(forKey: "HUD.Speed.enabled") == nil
            ? true
            : d.bool(forKey: "HUD.Speed.enabled")
        self.speedTolerance = d.object(forKey: "HUD.Speed.toleranceMph") == nil
            ? 0
            : max(0, min(30, d.integer(forKey: "HUD.Speed.toleranceMph")))
        self.showSpeedLimit = d.object(forKey: "HUD.Speed.showLimit") == nil
            ? true
            : d.bool(forKey: "HUD.Speed.showLimit")

        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = 4
        locationManager.pausesLocationUpdatesAutomatically = false

        if enabled {
            start()
        }
    }

    func start() {
        logger.log("SPEED", "Starting original-style GPS + OSM speed engine")
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        status = "Disabled"
    }

    func rehydrateHUDState() {
        guard enabled, bluetooth.state == .connected else { return }
        lastSentSpeed = -1
        lastSentLimit = -1

        logger.log(
            "SPEED SESSION",
            "Rehydrating HUD speed/limit state (showLimit=\(showSpeedLimit), tolerance=+\(speedTolerance) mph)"
        )

        if let location = locationManager.location {
            process(location)
        } else {
            resendCurrentLimitIfPossible()
        }

        if showSpeedLimit {
            refreshNow()
        }
    }

    private func resendCurrentLimitIfPossible() {
        guard bluetooth.state == .connected,
              showSpeedLimit,
              currentSpeedLimitMph > 0 else { return }

        bluetooth.enqueue(
            HudCommands.speedLimit(
                limit: currentSpeedLimitMph,
                tolerance: speedTolerance,
                squareStyle: true
            ),
            label: "Speed limit \(currentSpeedLimitMph) mph (+\(speedTolerance))"
        )
        bluetooth.enqueue(
            HudCommands.speedWarningThreshold(currentSpeedLimitMph + speedTolerance),
            label: "Speed warning \(currentSpeedLimitMph + speedTolerance) mph"
        )
        lastSentLimit = currentSpeedLimitMph
    }

    func refreshNow() {
        if let location = locationManager.location {
            lastQueryLocation = nil
            Task { await updateSegmentsIfNeeded(at: location) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.logger.log("LOCATION", "Authorization state \(manager.authorizationStatus.rawValue)")
            if self.enabled,
               manager.authorizationStatus == .authorizedAlways ||
               manager.authorizationStatus == .authorizedWhenInUse {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard self.enabled else { return }
            self.process(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.status = error.localizedDescription
            self.logger.log("LOCATION ERROR", error.localizedDescription)
        }
    }

    private func process(_ location: CLLocation) {
        let speedMS = max(0, location.speed)
        currentSpeedMph = Int((speedMS * 2.2369362920544).rounded())

        if currentSpeedMph != lastSentSpeed, bluetooth.state == .connected {
            lastSentSpeed = currentSpeedMph
            bluetooth.enqueue(
                HudCommands.speedNotification(kmh: currentSpeedMph),
                label: "Vehicle speed \(currentSpeedMph) mph"
            )
        }

        if let limit = bestSpeedLimit(at: location) {
            currentSpeedLimitMph = limit
            if showSpeedLimit, limit != lastSentLimit, bluetooth.state == .connected {
                lastSentLimit = limit
                bluetooth.enqueue(
                    HudCommands.speedLimit(limit: limit, tolerance: speedTolerance, squareStyle: true),
                    label: "Speed limit \(limit) mph (+\(speedTolerance))"
                )
                bluetooth.enqueue(
                    HudCommands.speedWarningThreshold(limit + speedTolerance),
                    label: "Speed warning \(limit + speedTolerance)"
                )
            }
            status = "GPS \(currentSpeedMph) mph • limit \(limit) mph"
        } else {
            status = "GPS \(currentSpeedMph) mph • finding speed limit…"
        }

        Task { await updateSegmentsIfNeeded(at: location) }
    }

    private func updateSegmentsIfNeeded(at location: CLLocation) async {
        if let lastQueryLocation, lastQueryLocation.distance(from: location) <= 300 {
            return
        }
        guard !requestInFlight else { return }
        requestInFlight = true
        defer { requestInFlight = false }

        // Matches the decompiled Android engine's 400 m Overpass query.
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let query = "[out:json];way[maxspeed][highway](around:400,\(lat),\(lon));out tags geom;"
        guard var comps = URLComponents(string: "https://overpass-api.de/api/interpreter") else { return }
        comps.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let url = comps.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let newSegments = decoded.elements.compactMap(Self.makeSegment)
            self.segments = newSegments
            self.lastQueryLocation = location
            self.logger.log("SPEED LIMIT", "Overpass loaded \(newSegments.count) maxspeed road segments")
        } catch {
            self.logger.log("SPEED LIMIT ERROR", error.localizedDescription)
            self.status = "Speed-limit lookup failed; GPS speed still active"
        }
    }

    private static func makeSegment(_ element: Element) -> Segment? {
        guard let maxspeed = element.tags?.maxspeed,
              let parsed = parseMaxSpeed(maxspeed),
              let geometry = element.geometry, geometry.count >= 2 else { return nil }
        return Segment(
            speedMph: parsed.mph,
            isMph: parsed.sourceWasMph,
            points: geometry.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        )
    }

    private static func parseMaxSpeed(_ raw: String) -> (mph: Int, sourceWasMph: Bool)? {
        let value = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if value.contains(";") {
            for part in value.split(separator: ";") {
                if let parsed = parseMaxSpeed(String(part)) { return parsed }
            }
        }

        let number = value
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .first
            .flatMap { Double($0) }

        if let number {
            // US/UK style OSM values such as "35 mph" remain unchanged.
            if value.contains("mph") {
                return (Int(number.rounded()), true)
            }

            // Knots -> mph.
            if value.contains("knots") {
                return (Int((number * 1.150779448).rounded()), false)
            }

            // Bare numeric maxspeed values in OSM are km/h by convention.
            // Convert them to mph for the entire HUD pipeline.
            return (Int((number * 0.62137119223733).rounded()), false)
        }

        // Symbolic defaults represented in mph.
        // These are intentionally conservative fallbacks corresponding to
        // common defaults used by the original engine's symbolic mapping.
        let defaultsMph: [String: Int] = [
            "us:urban": 25,
            "us:rural": 50,
            "de:urban": 31,
            "de:rural": 62,
            "fr:urban": 31,
            "fr:rural": 50,
            "gb:nsl_single": 60,
            "gb:nsl_dual": 70
        ]

        if let mph = defaultsMph[value] {
            return (mph, value.hasPrefix("us:") || value.hasPrefix("gb:"))
        }

        return nil
    }

    private func bestSpeedLimit(at location: CLLocation) -> Int? {
        guard !segments.isEmpty else { return nil }

        let heading = location.course >= 0 ? location.course : nil
        var best: (score: Double, speed: Int)?

        for segment in segments {
            for index in 0..<(segment.points.count - 1) {
                let a = segment.points[index]
                let b = segment.points[index + 1]
                let distance = Self.distanceFrom(location.coordinate, toSegmentA: a, b: b)
                if distance > 45 { continue }

                var score = distance
                if let heading {
                    let roadBearing = Self.bearing(from: a, to: b)
                    let delta = Self.angularDifference(heading, roadBearing)
                    let reverseDelta = Self.angularDifference(heading, fmod(roadBearing + 180, 360))
                    score += min(delta, reverseDelta) * 0.35
                }

                if best == nil || score < best!.score {
                    best = (score, segment.speedMph)
                }
            }
        }
        return best?.speed
    }

    private static func distanceFrom(
        _ p: CLLocationCoordinate2D,
        toSegmentA a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> Double {
        // Local equirectangular projection is accurate enough for <=400 m queries.
        let lat0 = p.latitude * .pi / 180
        let metersPerLat = 111_132.0
        let metersPerLon = 111_320.0 * cos(lat0)

        func xy(_ c: CLLocationCoordinate2D) -> (Double, Double) {
            ((c.longitude - p.longitude) * metersPerLon,
             (c.latitude - p.latitude) * metersPerLat)
        }

        let av = xy(a), bv = xy(b)
        let dx = bv.0 - av.0, dy = bv.1 - av.1
        let length2 = dx*dx + dy*dy
        guard length2 > 0 else { return hypot(av.0, av.1) }

        let t = max(0, min(1, -(av.0*dx + av.1*dy) / length2))
        return hypot(av.0 + t*dx, av.1 + t*dy)
    }

    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1)*sin(lat2) - sin(lat1)*cos(lat2)*cos(dLon)
        return fmod(atan2(y, x) * 180 / .pi + 360, 360)
    }

    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}
