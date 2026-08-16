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

    struct SegmentPart {
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D
        let shiftedStart: CLLocationCoordinate2D
        let shiftedEnd: CLLocationCoordinate2D
        let direction: Double
    }

    struct Segment {
        let speedKmh: Int
        let sourceWasMph: Bool
        let points: [CLLocationCoordinate2D]
        let parts: [SegmentPart]
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
        self.currentSpeedLimitMph = max(0, d.integer(forKey: "HUD.Speed.lastKnownLimitMph"))

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


    /// Immediately overwrite the firmware's circular boot-default style.
    ///
    /// A zero limit is used as a style-only/hidden prime so we don't show a
    /// stale road limit from the previous drive. The first valid GPS/OSM
    /// result then replaces it with the real rectangular sign.
    func primeRectangularStyle() {
        guard enabled, showSpeedLimit, bluetooth.state == .connected else { return }

        bluetooth.enqueue(
            HudCommands.speedLimit(limit: 0, tolerance: speedTolerance),
            label: "Speed-limit rectangle style prime"
        )
        lastSentLimit = -1
        logger.log("SPEED SESSION", "Primed rectangular speed-limit style immediately")
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
                tolerance: speedTolerance
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
        // CLLocation.speed is meters/second. The HUD protocol's native
        // SpeedNotification field is km/h even when the physical HUD is
        // configured to DISPLAY mph. Previous builds incorrectly placed the
        // mph number into this km/h field, producing ~0.62x displayed speed
        // (for example 45 mph becoming about 28 mph).
        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard location.speed >= 0,
              age <= 5,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 65 else {
            logger.log(
                "GPS SPEED REJECT",
                "age=\(String(format: "%.1f", age))s accuracy=\(Int(location.horizontalAccuracy))m speed=\(location.speed)"
            )
            return
        }

        let speedMS = location.speed
        let protocolSpeedKmh = Int((speedMS * 3.6).rounded())
        currentSpeedMph = Int((speedMS * 2.2369362920544).rounded())

        if currentSpeedMph != lastSentSpeed, bluetooth.state == .connected {
            lastSentSpeed = currentSpeedMph
            bluetooth.enqueue(
                HudCommands.speedNotification(kmh: protocolSpeedKmh),
                label: "Vehicle speed \(currentSpeedMph) mph (HUD protocol \(protocolSpeedKmh) km/h)"
            )
        }

        if let limit = bestSpeedLimit(at: location) {
            currentSpeedLimitMph = limit
            UserDefaults.standard.set(limit, forKey: "HUD.Speed.lastKnownLimitMph")
            if showSpeedLimit, limit != lastSentLimit, bluetooth.state == .connected {
                lastSentLimit = limit
                bluetooth.enqueue(
                    HudCommands.speedLimit(limit: limit, tolerance: speedTolerance),
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
            self.logger.log(
                "SPEED LIMIT",
                "Original HUDWAY matcher loaded \(newSegments.count) roads (400m query / 30m corridor / bearing+15m score)"
            )
        } catch {
            self.logger.log("SPEED LIMIT ERROR", error.localizedDescription)
            self.status = "Speed-limit lookup failed; GPS speed still active"
        }
    }

    private static func makeSegment(_ element: Element) -> Segment? {
        guard let maxspeed = element.tags?.maxspeed,
              let parsed = parseOriginalMaxSpeed(maxspeed),
              let geometry = element.geometry,
              geometry.count >= 2 else { return nil }

        let points = geometry.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }

        var parts: [SegmentPart] = []
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let heading = bearing(from: start, to: end)

            parts.append(
                SegmentPart(
                    start: start,
                    end: end,
                    shiftedStart: coordinate(
                        from: start,
                        distanceMeters: 30,
                        bearingDegrees: heading + 90
                    ),
                    shiftedEnd: coordinate(
                        from: end,
                        distanceMeters: 30,
                        bearingDegrees: heading - 90
                    ),
                    direction: heading
                )
            )
        }

        return Segment(
            speedKmh: parsed.kmh,
            sourceWasMph: parsed.sourceWasMph,
            points: points,
            parts: parts
        )
    }

    private static func parseOriginalMaxSpeed(
        _ raw: String
    ) -> (kmh: Int, sourceWasMph: Bool)? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let direct = Int(value) {
            return (direct, false)
        }

        if value.lowercased().contains("mph") {
            let cleaned = value.lowercased()
                .replacingOccurrences(of: "mph", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let mph = Int(cleaned) {
                return (Int((Double(mph) * 1.609344).rounded()), true)
            }
        }

        let symbolic: [String: String] = [
            "UK:motorway": "70 mph",
            "CA-BC:rural": "80",
            "CA-BC:urban": "50",
            "CA-MB:rural": "90",
            "CA-MB:urban": "50",
            "CA-ON:rural": "80",
            "CA-QC:motorway": "100",
            "CA-QC:urban": "50",
            "CA-SK:nsl": "80"
        ]

        if let mapped = symbolic[value] {
            return parseOriginalMaxSpeed(mapped)
        }

        return nil
    }

    private func bestSpeedLimit(at location: CLLocation) -> Int? {
        guard !segments.isEmpty else { return nil }

        let direction = location.course >= 0 ? location.course : 0
        var best: (score: Double, kmh: Int)?

        for segment in segments {
            let eligibleParts = segment.parts.filter {
                Self.originalPolygonContains(
                    $0,
                    location: location.coordinate
                )
            }

            guard !eligibleParts.isEmpty else { continue }

            var segmentScore = Double.greatestFiniteMagnitude

            for part in eligibleParts {
                let angle = Self.angularDifference(
                    part.direction,
                    direction
                )
                let distance = Self.distanceFrom(
                    location.coordinate,
                    toSegmentA: part.start,
                    b: part.end
                )

                let score =
                    (angle < 45 ? angle / 45 : 2) +
                    (distance < 15 ? distance / 15 : 2)

                segmentScore = min(segmentScore, score)
            }

            if best == nil || segmentScore < best!.score {
                best = (segmentScore, segment.speedKmh)
            }
        }

        guard let kmh = best?.kmh, kmh >= 0 else { return nil }
        return Int((Double(kmh) / 1.609344).rounded())
    }

    private static func originalPolygonContains(
        _ part: SegmentPart,
        location: CLLocationCoordinate2D
    ) -> Bool {
        let a = CLLocation(
            latitude: part.shiftedStart.latitude,
            longitude: part.shiftedStart.longitude
        )
        let b = CLLocation(
            latitude: part.shiftedEnd.latitude,
            longitude: part.shiftedEnd.longitude
        )
        let p = CLLocation(
            latitude: location.latitude,
            longitude: location.longitude
        )

        let da = a.distance(from: p)
        let db = b.distance(from: p)
        let length = a.distance(from: b)

        return da * da + db * db < length * length
    }

    private static func coordinate(
        from coordinate: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_372_797.6
        let angularDistance = distanceMeters / earthRadius
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180

        let lat2 = asin(
            sin(lat1) * cos(angularDistance) +
            cos(lat1) * sin(angularDistance) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
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
