import Foundation
import CoreLocation
import Observation

enum SpeedLimitSourceMode: String, CaseIterable, Identifiable {
    case current = "Current"
    case enhancedOSM = "Enhanced OSM"
    case traceOSM = "OSM Trace"

    var id: String { rawValue }

    var shortDescription: String {
        switch self {
        case .current:
            return "Original decompiled HUDWAY OSM matcher"
        case .enhancedOSM:
            return "Enhanced OSM directional + continuity matcher"
        case .traceOSM:
            return "Rolling GPS-trace map matcher using OSM only"
        }
    }
}

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
        let maxspeedForward: String?
        let maxspeedBackward: String?
        let maxspeedConditional: String?
        let maxspeedForwardConditional: String?
        let maxspeedBackwardConditional: String?
        let oneway: String?
        let name: String?
        let ref: String?

        enum CodingKeys: String, CodingKey {
            case highway
            case maxspeed
            case maxspeedForward = "maxspeed:forward"
            case maxspeedBackward = "maxspeed:backward"
            case maxspeedConditional = "maxspeed:conditional"
            case maxspeedForwardConditional = "maxspeed:forward:conditional"
            case maxspeedBackwardConditional = "maxspeed:backward:conditional"
            case oneway
            case name
            case ref
        }
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

    struct EnhancedSegment {
        let elementID: Int64
        let highway: String
        let name: String?
        let reference: String?
        let baseKmh: Int?
        let forwardKmh: Int?
        let backwardKmh: Int?
        let baseConditional: String?
        let forwardConditional: String?
        let backwardConditional: String?
        let parts: [SegmentPart]
    }

    struct EnhancedCandidate {
        let elementID: Int64
        let speedMph: Int
        let score: Double
    }

    struct TraceCandidate {
        let elementID: Int64
        let speedMph: Int
        let score: Double
        let confidenceMargin: Double
    }

    private let locationManager = CLLocationManager()
    private let bluetooth: HudBluetoothManager
    private let logger: LogManager

    private var segments: [Segment] = []
    private var enhancedSegments: [EnhancedSegment] = []
    private var lastQueryLocation: CLLocation?
    private var requestInFlight = false
    private var lastSentSpeed = -1
    private var lastSentLimit = -1

    private var enhancedCurrentSegmentID: Int64?
    private var enhancedPendingCandidate: (id: Int64, mph: Int, count: Int)?
    private var traceLocations: [CLLocation] = []
    private var traceCurrentSegmentID: Int64?
    private var tracePendingCandidate: (id: Int64, mph: Int, count: Int)?
    private var traceLastConfidenceMargin: Double = 0

    private(set) var currentSpeedMph = 0
    private(set) var currentSpeedLimitMph = 0
    /// Warning eligibility is intentionally stricter than merely having a cached
    /// integer limit. A previous-drive UserDefaults value must never arm a red-light
    /// warning before the currently selected matcher has resolved a live road limit.
    private(set) var speedLimitAvailableForWarning = false
    private var lastResolvedLimitAt: Date?
    private let warningLimitFreshnessSeconds: TimeInterval = 12.0
    private(set) var status = "Waiting for location"
    private(set) var sourceDetail = "Current • original matcher"

    /// v90.12: publishes the same iPhone GPS speed and currently displayed
    /// speed-limit availability to the ambient warning controller.
    var onSpeedStateChanged: ((Int, Int, Bool) -> Void)?

    var sourceMode: SpeedLimitSourceMode {
        didSet {
            UserDefaults.standard.set(sourceMode.rawValue, forKey: "HUD.Speed.limitSource")
            resetProviderStateForSourceChange()
            if enabled { refreshNow() }
        }
    }


    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "HUD.Speed.enabled")
            if enabled { start() } else { stop() }
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
            refreshWarningLimitAvailability(now: Date())
            onSpeedStateChanged?(
                currentSpeedMph,
                currentSpeedLimitMph,
                speedLimitAvailableForWarning
            )
        }
    }

    init(bluetooth: HudBluetoothManager, logger: LogManager) {
        self.bluetooth = bluetooth
        self.logger = logger

        let d = UserDefaults.standard
        self.enabled = d.object(forKey: "HUD.Speed.enabled") == nil
            ? true
            : d.bool(forKey: "HUD.Speed.enabled")
        // Remove the custom app-side tolerance introduced by earlier builds.
        // Stock HUDWAY Drive 1.4.6 defaults to Automatic alerts with
        // SPEED_TOLERANCE_VALUE = 0.
        d.removeObject(forKey: "HUD.Speed.toleranceMph")
        self.showSpeedLimit = d.object(forKey: "HUD.Speed.showLimit") == nil
            ? true
            : d.bool(forKey: "HUD.Speed.showLimit")
        self.currentSpeedLimitMph = max(0, d.integer(forKey: "HUD.Speed.lastKnownLimitMph"))
        self.sourceMode = SpeedLimitSourceMode(
            rawValue: d.string(forKey: "HUD.Speed.limitSource") ?? ""
        ) ?? .current

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
        // A cached last-known sign may still be useful to the UI, but it is not
        // fresh enough to drive an ambient safety warning until this session's
        // matcher resolves it again.
        lastResolvedLimitAt = nil
        speedLimitAvailableForWarning = false
        onSpeedStateChanged?(currentSpeedMph, currentSpeedLimitMph, false)
        logger.log("SPEED", "Starting original-style GPS + OSM speed engine")
        logger.log("SPEED LIMIT", "Selected source = \(sourceMode.rawValue)")
        locationManager.requestAlwaysAuthorization()
        locationManager.startUpdatingLocation()
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        status = "Disabled"
        lastResolvedLimitAt = nil
        speedLimitAvailableForWarning = false
        onSpeedStateChanged?(currentSpeedMph, currentSpeedLimitMph, false)
    }

    /// Immediately overwrite the firmware's circular boot-default style.
    ///
    /// A zero limit is used as a style-only/hidden prime so we don't show a
    /// stale road limit from the previous drive. The first valid GPS/OSM
    /// result then replaces it with the real rectangular sign.
    func primeRectangularStyle() {
        guard enabled, showSpeedLimit, bluetooth.state == .connected else { return }

        bluetooth.enqueue(
            HudCommands.speedLimit(limit: 0, tolerance: 0),
            label: "Speed-limit rectangle style prime (display tolerance 0)"
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
            "Rehydrating HUD speed/limit state (showLimit=\(showSpeedLimit), originalAutoWarning=postedLimit)"
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

    /// Decompiled stock HUDWAY Drive 1.4.6 Automatic mode:
    /// DisplaySpeedWarningCommandPacket.setSpeedThreshold(speedLimitValue).
    ///
    /// The stock defaults are SPEED_ALERTS_METHOD=0 and
    /// SPEED_TOLERANCE_VALUE=0, so the warning follows the posted limit
    /// exactly. Do not add an app-side tolerance.
    private func sendOriginalAutomaticSpeedWarning(
        legalLimitMph: Int
    ) {
        guard legalLimitMph > 0,
              bluetooth.state == .connected else { return }

        bluetooth.enqueue(
            HudCommands.speedWarningThreshold(legalLimitMph),
            label: "Original auto speed warning threshold = posted limit \(legalLimitMph) mph"
        )
    }

    private func resendCurrentLimitIfPossible() {
        guard bluetooth.state == .connected,
              showSpeedLimit,
              currentSpeedLimitMph > 0 else { return }

        bluetooth.enqueue(
            HudCommands.speedLimit(
                limit: currentSpeedLimitMph,
                tolerance: 0
            ),
            label: "Speed limit \(currentSpeedLimitMph) mph (tolerance 0)"
        )
        sendOriginalAutomaticSpeedWarning(
            legalLimitMph: currentSpeedLimitMph
        )
        lastSentLimit = currentSpeedLimitMph
    }

    func refreshNow() {
        if let location = locationManager.location {
            lastQueryLocation = nil
            Task { await updateProviderDataIfNeeded(at: location, force: true) }
        }
    }

    private func resetProviderStateForSourceChange() {
        segments.removeAll()
        enhancedSegments.removeAll()
        enhancedCurrentSegmentID = nil
        enhancedPendingCandidate = nil
        traceLocations.removeAll()
        traceCurrentSegmentID = nil
        tracePendingCandidate = nil
        traceLastConfidenceMargin = 0
        lastQueryLocation = nil
        requestInFlight = false
        currentSpeedLimitMph = 0
        lastResolvedLimitAt = nil
        speedLimitAvailableForWarning = false
        lastSentLimit = -1
        sourceDetail = "\(sourceMode.rawValue) • waiting for data"

        if bluetooth.state == .connected, showSpeedLimit {
            bluetooth.enqueue(
                HudCommands.speedLimit(limit: 0, tolerance: 0),
                label: "Speed-limit source changed → clear stale sign"
            )
        }
        logger.log("SPEED LIMIT", "Speed-limit source changed to \(sourceMode.rawValue)")
        onSpeedStateChanged?(currentSpeedMph, 0, false)
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

        appendTraceLocation(location)

        let limit: Int?
        switch sourceMode {
        case .current:
            limit = bestSpeedLimit(at: location)
            sourceDetail = "Current • original OSM"
        case .enhancedOSM:
            limit = bestEnhancedSpeedLimit(at: location)
            sourceDetail = "Enhanced OSM • directional/continuity"
        case .traceOSM:
            logger.log(
                "OSM TRACE GPS",
                String(
                    format: "lat=%.6f lon=%.6f acc=%.1fm course=%.1f speed=%.1fmps(%dmph) traceStored=%d",
                    location.coordinate.latitude,
                    location.coordinate.longitude,
                    location.horizontalAccuracy,
                    location.course,
                    location.speed,
                    currentSpeedMph,
                    traceLocations.count
                )
            )
            limit = bestTraceSpeedLimit(at: location)
            logger.log(
                "OSM TRACE OUTPUT",
                String(
                    format: "gps=%.6f,%.6f resolved=%@ currentWay=%@ pending=%@ margin=%.2f",
                    location.coordinate.latitude,
                    location.coordinate.longitude,
                    limit.map { "\($0)mph" } ?? "none",
                    traceCurrentSegmentID.map { String($0) } ?? "none",
                    tracePendingCandidate.map { "\($0.id):\($0.mph)mph#\($0.count)" } ?? "none",
                    traceLastConfidenceMargin
                )
            )
            sourceDetail = String(
                format: "OSM Trace • rolling trace • margin %.2f",
                traceLastConfidenceMargin
            )
        }

        if let limit, limit > 0 {
            applyResolvedLimit(limit)
            status = "\(sourceMode.rawValue) • GPS \(currentSpeedMph) mph • limit \(limit) mph"
        } else {
            status = "\(sourceMode.rawValue) • GPS \(currentSpeedMph) mph • finding speed limit…"
        }

        // Warning requires a live/fresh resolution from the currently selected
        // matcher. A cached prior-drive limit can remain visible elsewhere, but it
        // cannot arm the red warning. If no road has matched for 12 seconds the
        // warning becomes unavailable until a fresh limit resolves again.
        refreshWarningLimitAvailability(now: Date())
        onSpeedStateChanged?(
            currentSpeedMph,
            currentSpeedLimitMph,
            speedLimitAvailableForWarning
        )

        Task { await updateProviderDataIfNeeded(at: location, force: false) }
    }

    private func applyResolvedLimit(_ limit: Int) {
        currentSpeedLimitMph = limit
        lastResolvedLimitAt = Date()
        speedLimitAvailableForWarning = showSpeedLimit && limit > 0
        UserDefaults.standard.set(limit, forKey: "HUD.Speed.lastKnownLimitMph")
        if showSpeedLimit, limit != lastSentLimit, bluetooth.state == .connected {
            lastSentLimit = limit
            bluetooth.enqueue(
                HudCommands.speedLimit(limit: limit, tolerance: 0),
                label: "Speed limit \(limit) mph (tolerance 0) source=\(sourceMode.rawValue)"
            )
            sendOriginalAutomaticSpeedWarning(
                legalLimitMph: limit
            )
        }
    }

    private func refreshWarningLimitAvailability(now: Date) {
        guard showSpeedLimit,
              currentSpeedLimitMph > 0,
              let lastResolvedLimitAt,
              now.timeIntervalSince(lastResolvedLimitAt) <= warningLimitFreshnessSeconds else {
            speedLimitAvailableForWarning = false
            return
        }
        speedLimitAvailableForWarning = true
    }

    private func updateProviderDataIfNeeded(at location: CLLocation, force: Bool) async {
        switch sourceMode {
        case .current:
            await updateOriginalSegmentsIfNeeded(at: location, force: force)
        case .enhancedOSM, .traceOSM:
            await updateEnhancedSegmentsIfNeeded(at: location, force: force)
        }
    }

    // MARK: - Current / original OSM matcher

    private func updateOriginalSegmentsIfNeeded(at location: CLLocation, force: Bool) async {
        if !force, let lastQueryLocation, lastQueryLocation.distance(from: location) <= 300 {
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
            self.logger.log("SPEED LIMIT ERROR", "Current OSM: \(error.localizedDescription)")
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

        let parts = makeParts(points)
        return Segment(
            speedKmh: parsed.kmh,
            sourceWasMph: parsed.sourceWasMph,
            points: points,
            parts: parts
        )
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

    // MARK: - Enhanced OSM matcher

    private func updateEnhancedSegmentsIfNeeded(at location: CLLocation, force: Bool) async {
        if !force, let lastQueryLocation, lastQueryLocation.distance(from: location) <= 200 {
            return
        }
        guard !requestInFlight else { return }
        requestInFlight = true
        defer { requestInFlight = false }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let query = """
        [out:json];
        (
          way[highway][maxspeed](around:500,\(lat),\(lon));
          way[highway]["maxspeed:forward"](around:500,\(lat),\(lon));
          way[highway]["maxspeed:backward"](around:500,\(lat),\(lon));
          way[highway]["maxspeed:conditional"](around:500,\(lat),\(lon));
          way[highway]["maxspeed:forward:conditional"](around:500,\(lat),\(lon));
          way[highway]["maxspeed:backward:conditional"](around:500,\(lat),\(lon));
        );
        out tags geom;
        """
        guard var comps = URLComponents(string: "https://overpass-api.de/api/interpreter") else { return }
        comps.queryItems = [URLQueryItem(name: "data", value: query)]
        guard let url = comps.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let newSegments = decoded.elements.compactMap(Self.makeEnhancedSegment)
            self.enhancedSegments = newSegments
            self.lastQueryLocation = location
            self.logger.log(
                "SPEED LIMIT",
                "OSM experimental matcher loaded \(newSegments.count) roads (500m query / directional+conditional maxspeed / continuity+trace scoring)"
            )
            if self.sourceMode == .traceOSM {
                self.logger.log(
                    "OSM TRACE QUERY",
                    String(format: "center=%.6f,%.6f radius=500m roads=%d", lat, lon, newSegments.count)
                )
            }
        } catch {
            self.logger.log("SPEED LIMIT ERROR", "Enhanced OSM: \(error.localizedDescription)")
            self.status = "Enhanced OSM lookup failed; GPS speed still active"
        }
    }

    private static func makeEnhancedSegment(_ element: Element) -> EnhancedSegment? {
        guard let tags = element.tags,
              let highway = tags.highway,
              let geometry = element.geometry,
              geometry.count >= 2 else { return nil }

        let base = tags.maxspeed.flatMap { parseOriginalMaxSpeed($0)?.kmh }
        let forward = tags.maxspeedForward.flatMap { parseOriginalMaxSpeed($0)?.kmh }
        let backward = tags.maxspeedBackward.flatMap { parseOriginalMaxSpeed($0)?.kmh }
        guard base != nil || forward != nil || backward != nil else { return nil }

        let points = geometry.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        return EnhancedSegment(
            elementID: element.id,
            highway: highway,
            name: tags.name,
            reference: tags.ref,
            baseKmh: base,
            forwardKmh: forward,
            backwardKmh: backward,
            baseConditional: tags.maxspeedConditional,
            forwardConditional: tags.maxspeedForwardConditional,
            backwardConditional: tags.maxspeedBackwardConditional,
            parts: makeParts(points)
        )
    }

    private func bestEnhancedSpeedLimit(at location: CLLocation) -> Int? {
        guard !enhancedSegments.isEmpty else { return nil }
        let course = location.course >= 0 ? location.course : 0
        var best: EnhancedCandidate?

        for segment in enhancedSegments {
            for part in segment.parts {
                let distance = Self.distanceFrom(
                    location.coordinate,
                    toSegmentA: part.start,
                    b: part.end
                )
                guard distance <= 45 else { continue }

                let forwardAngle = Self.angularDifference(part.direction, course)
                let reverseAngle = Self.angularDifference(
                    fmod(part.direction + 180, 360),
                    course
                )
                let travelingForward = forwardAngle <= reverseAngle
                let angle = min(forwardAngle, reverseAngle)
                guard angle <= 100 else { continue }

                guard let kmh = Self.resolvedKmh(
                    for: segment,
                    travelingForward: travelingForward,
                    at: location.timestamp
                ), kmh > 0 else { continue }

                var score =
                    min(3.0, angle / 30.0) +
                    min(3.0, distance / 20.0)

                if segment.elementID == enhancedCurrentSegmentID {
                    score -= 0.85
                }
                if let pending = enhancedPendingCandidate, pending.id == segment.elementID {
                    score -= 0.25
                }

                let mph = Int((Double(kmh) / 1.609344).rounded())
                let candidate = EnhancedCandidate(
                    elementID: segment.elementID,
                    speedMph: mph,
                    score: score
                )
                if best == nil || candidate.score < best!.score {
                    best = candidate
                }
            }
        }

        guard let candidate = best else { return nil }

        if candidate.elementID == enhancedCurrentSegmentID {
            enhancedPendingCandidate = nil
            return candidate.speedMph
        }

        if let pending = enhancedPendingCandidate,
           pending.id == candidate.elementID,
           pending.mph == candidate.speedMph {
            let next = pending.count + 1
            enhancedPendingCandidate = (candidate.elementID, candidate.speedMph, next)
            if next >= 2 {
                enhancedCurrentSegmentID = candidate.elementID
                enhancedPendingCandidate = nil
                return candidate.speedMph
            }
        } else {
            enhancedPendingCandidate = (candidate.elementID, candidate.speedMph, 1)
        }

        // Hold the previous accepted limit for one GPS sample to prevent frontage
        // roads / ramps / parallel links from instantly stealing the match.
        if currentSpeedLimitMph > 0 {
            return currentSpeedLimitMph
        }
        return nil
    }

    // MARK: - OSM rolling-trace matcher (no commercial API)

    private func appendTraceLocation(_ location: CLLocation) {
        if let last = traceLocations.last, last.distance(from: location) < 4 {
            return
        }
        traceLocations.append(location)
        if traceLocations.count > 10 {
            traceLocations.removeFirst(traceLocations.count - 10)
        }
    }

    private func bestTraceSpeedLimit(at location: CLLocation) -> Int? {
        guard !enhancedSegments.isEmpty else {
            logger.log("OSM TRACE MATCH", "no OSM road dataset loaded yet; waiting for 500m query")
            return nil
        }

        let trace = Array(traceLocations.suffix(8))
        guard !trace.isEmpty else {
            logger.log("OSM TRACE MATCH", "no accepted GPS trace points yet")
            return nil
        }

        var scored: [(
            segment: EnhancedSegment,
            score: Double,
            speedMph: Int,
            currentDistance: Double,
            currentAngle: Double,
            matchedPoints: Int,
            forward: Bool,
            nearestStart: CLLocationCoordinate2D,
            nearestEnd: CLLocationCoordinate2D
        )] = []

        for segment in enhancedSegments {
            guard !segment.parts.isEmpty else { continue }

            // The newest point must still be plausibly on this road. This prevents
            // history from pinning us to a road after a real turn or ramp transition.
            let currentCourse = location.course >= 0 ? location.course : 0
            var currentBest: (
                distance: Double,
                angle: Double,
                forward: Bool,
                start: CLLocationCoordinate2D,
                end: CLLocationCoordinate2D
            )?
            for part in segment.parts {
                let distance = Self.distanceFrom(
                    location.coordinate,
                    toSegmentA: part.start,
                    b: part.end
                )
                let forwardAngle = Self.angularDifference(part.direction, currentCourse)
                let reverseAngle = Self.angularDifference(fmod(part.direction + 180, 360), currentCourse)
                let forward = forwardAngle <= reverseAngle
                let angle = min(forwardAngle, reverseAngle)
                if currentBest == nil || distance + angle * 0.15 < currentBest!.distance + currentBest!.angle * 0.15 {
                    currentBest = (distance, angle, forward, part.start, part.end)
                }
            }
            guard let currentBest, currentBest.distance <= 55, currentBest.angle <= 105 else { continue }
            guard let kmh = Self.resolvedKmh(
                for: segment,
                travelingForward: currentBest.forward,
                at: location.timestamp
            ), kmh > 0 else { continue }

            var weightedScore = 0.0
            var totalWeight = 0.0
            var matchedPoints = 0

            for (index, sample) in trace.enumerated() {
                let weight = Double(index + 1)
                let course = sample.course >= 0 ? sample.course : currentCourse
                var pointBest = Double.greatestFiniteMagnitude

                for part in segment.parts {
                    let distance = Self.distanceFrom(
                        sample.coordinate,
                        toSegmentA: part.start,
                        b: part.end
                    )
                    guard distance <= 80 else { continue }
                    let forwardAngle = Self.angularDifference(part.direction, course)
                    let reverseAngle = Self.angularDifference(fmod(part.direction + 180, 360), course)
                    let angle = min(forwardAngle, reverseAngle)
                    let local = min(4.0, distance / 18.0) + min(3.0, angle / 35.0)
                    pointBest = min(pointBest, local)
                }

                if pointBest.isFinite {
                    matchedPoints += 1
                    weightedScore += pointBest * weight
                } else {
                    weightedScore += 7.0 * weight
                }
                totalWeight += weight
            }

            guard matchedPoints >= max(1, trace.count / 2) else { continue }
            var score = weightedScore / max(1.0, totalWeight)

            if segment.elementID == traceCurrentSegmentID {
                score -= 0.75
            }
            if let pending = tracePendingCandidate, pending.id == segment.elementID {
                score -= 0.20
            }

            let mph = Int((Double(kmh) / 1.609344).rounded())
            scored.append((
                segment,
                score,
                mph,
                currentBest.distance,
                currentBest.angle,
                matchedPoints,
                currentBest.forward,
                currentBest.start,
                currentBest.end
            ))
        }

        scored.sort { $0.score < $1.score }

        let tracePoints = trace.map { sample in
            String(
                format: "%.6f,%.6f,c=%.0f,a=%.0f",
                sample.coordinate.latitude,
                sample.coordinate.longitude,
                sample.course,
                sample.horizontalAccuracy
            )
        }.joined(separator: ";")
        logger.log("OSM TRACE PATH", "points=[\(tracePoints)]")

        guard let best = scored.first else {
            logger.log(
                "OSM TRACE MATCH",
                "no eligible road candidate; holding=\(currentSpeedLimitMph > 0 ? "\(currentSpeedLimitMph)mph" : "none")"
            )
            return currentSpeedLimitMph > 0 ? currentSpeedLimitMph : nil
        }

        let topSummary = scored.prefix(4).map { candidate in
            let name = (candidate.segment.name ?? "-").replacingOccurrences(of: "|", with: "/")
            let ref = (candidate.segment.reference ?? "-").replacingOccurrences(of: "|", with: "/")
            let base = candidate.segment.baseKmh.map { String($0) } ?? "-"
            let forward = candidate.segment.forwardKmh.map { String($0) } ?? "-"
            let backward = candidate.segment.backwardKmh.map { String($0) } ?? "-"
            return String(
                format: "way=%lld name=%@ ref=%@ highway=%@ limit=%d score=%.2f dist=%.1fm angle=%.1f matched=%d/%d dir=%@ seg=%.6f,%.6f>%.6f,%.6f speedTags=%@/%@/%@",
                candidate.segment.elementID,
                name,
                ref,
                candidate.segment.highway,
                candidate.speedMph,
                candidate.score,
                candidate.currentDistance,
                candidate.currentAngle,
                candidate.matchedPoints,
                trace.count,
                candidate.forward ? "F" : "R",
                candidate.nearestStart.latitude,
                candidate.nearestStart.longitude,
                candidate.nearestEnd.latitude,
                candidate.nearestEnd.longitude,
                base,
                forward,
                backward
            )
        }.joined(separator: " | ")
        logger.log(
            "OSM TRACE MATCH",
            "currentWay=\(traceCurrentSegmentID.map { String($0) } ?? "none") pending=\(tracePendingCandidate.map { "\($0.id):\($0.mph)mph#\($0.count)" } ?? "none") top=[\(topSummary)]"
        )
        let secondScore = scored.dropFirst().first?.score ?? (best.score + 3.0)
        let margin = max(0, secondScore - best.score)
        traceLastConfidenceMargin = margin

        if best.segment.elementID == traceCurrentSegmentID {
            tracePendingCandidate = nil
            logger.log(
                "OSM TRACE DECISION",
                String(format: "retain current way=%lld limit=%d score=%.2f margin=%.2f", best.segment.elementID, best.speedMph, best.score, margin)
            )
            return best.speedMph
        }

        // Require both a score advantage and repeated evidence before changing roads.
        // This is intentionally conservative around frontage roads, divided highways,
        // parking-lot aisles and ramps.
        let strongEnough = margin >= 0.30 || traceCurrentSegmentID == nil
        if strongEnough {
            if let pending = tracePendingCandidate,
               pending.id == best.segment.elementID,
               pending.mph == best.speedMph {
                let next = pending.count + 1
                tracePendingCandidate = (best.segment.elementID, best.speedMph, next)
                logger.log(
                    "OSM TRACE DECISION",
                    String(format: "confirm pending way=%lld limit=%d score=%.2f margin=%.2f confirmation=%d/2", best.segment.elementID, best.speedMph, best.score, margin, next)
                )
                if next >= 2 {
                    traceCurrentSegmentID = best.segment.elementID
                    tracePendingCandidate = nil
                    logger.log(
                        "SPEED LIMIT",
                        String(
                            format: "OSM Trace accepted way=%lld limit=%d mph score=%.2f margin=%.2f trace=%d",
                            best.segment.elementID,
                            best.speedMph,
                            best.score,
                            margin,
                            trace.count
                        )
                    )
                    return best.speedMph
                }
            } else {
                tracePendingCandidate = (best.segment.elementID, best.speedMph, 1)
                logger.log(
                    "OSM TRACE DECISION",
                    String(format: "new pending way=%lld limit=%d score=%.2f margin=%.2f confirmation=1/2", best.segment.elementID, best.speedMph, best.score, margin)
                )
            }
        } else {
            logger.log(
                "OSM TRACE DECISION",
                String(format: "reject switch way=%lld limit=%d score=%.2f margin=%.2f(<0.30); holding=%d", best.segment.elementID, best.speedMph, best.score, margin, currentSpeedLimitMph)
            )
        }

        return currentSpeedLimitMph > 0 ? currentSpeedLimitMph : nil
    }

    private static func resolvedKmh(
        for segment: EnhancedSegment,
        travelingForward: Bool,
        at date: Date
    ) -> Int? {
        let directionalConditional = travelingForward
            ? segment.forwardConditional
            : segment.backwardConditional
        if let raw = directionalConditional,
           let conditional = parseSimpleConditionalMaxSpeed(raw, at: date) {
            return conditional
        }
        if let raw = segment.baseConditional,
           let conditional = parseSimpleConditionalMaxSpeed(raw, at: date) {
            return conditional
        }

        if travelingForward {
            return segment.forwardKmh ?? segment.baseKmh ?? segment.backwardKmh
        }
        return segment.backwardKmh ?? segment.baseKmh ?? segment.forwardKmh
    }

    /// Conservative evaluator for common OSM time/day conditional limits.
    /// Unsupported conditions (wet, snow, flashing lights, children_present, PH,
    /// vehicle-specific clauses, etc.) are ignored rather than guessed.
    private static func parseSimpleConditionalMaxSpeed(_ raw: String, at date: Date) -> Int? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date) // 1=Su ... 7=Sa
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)

        func dayIndex(_ token: String) -> Int? {
            switch token {
            case "Su": return 1
            case "Mo": return 2
            case "Tu": return 3
            case "We": return 4
            case "Th": return 5
            case "Fr": return 6
            case "Sa": return 7
            default: return nil
            }
        }

        func dayMatches(_ spec: String) -> Bool {
            let pieces = spec.split(separator: ",").map(String.init)
            for piece in pieces {
                if piece.contains("-") {
                    let ends = piece.split(separator: "-").map(String.init)
                    if ends.count == 2, let a = dayIndex(ends[0]), let b = dayIndex(ends[1]) {
                        if a <= b, (a...b).contains(weekday) { return true }
                        if a > b, weekday >= a || weekday <= b { return true }
                    }
                } else if dayIndex(piece) == weekday {
                    return true
                }
            }
            return false
        }

        func timeMatches(_ spec: String) -> Bool? {
            let ends = spec.split(separator: "-").map(String.init)
            guard ends.count == 2 else { return nil }
            func parse(_ value: String) -> Int? {
                let parts = value.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                return parts[0] * 60 + parts[1]
            }
            guard let a = parse(ends[0]), let b = parse(ends[1]) else { return nil }
            return a <= b ? (minute >= a && minute <= b) : (minute >= a || minute <= b)
        }

        for clause in raw.split(separator: ";") {
            let pair = clause.split(separator: "@", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pair.count == 2, let parsed = parseOriginalMaxSpeed(pair[0]) else { continue }
            var condition = pair[1]
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let unsupported = ["wet", "snow", "ice", "flashing", "children", "school", "PH", "weight", "hgv", "bus", "vehicle"]
            if unsupported.contains(where: { condition.localizedCaseInsensitiveContains($0) }) {
                continue
            }

            let tokens = condition.split(whereSeparator: { $0 == " " || $0 == "&" }).map(String.init)
            var sawRecognized = false
            var matches = true
            for token in tokens where !token.isEmpty {
                if token.contains(":") && token.contains("-") {
                    guard let result = timeMatches(token) else { matches = false; break }
                    sawRecognized = true
                    matches = matches && result
                } else if token.range(of: #"^(Mo|Tu|We|Th|Fr|Sa|Su)(-(Mo|Tu|We|Th|Fr|Sa|Su))?(,(Mo|Tu|We|Th|Fr|Sa|Su)(-(Mo|Tu|We|Th|Fr|Sa|Su))?)*$"#, options: .regularExpression) != nil {
                    sawRecognized = true
                    matches = matches && dayMatches(token)
                } else {
                    matches = false
                    break
                }
            }
            if sawRecognized && matches { return parsed.kmh }
        }
        return nil
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

    private static func makeParts(_ points: [CLLocationCoordinate2D]) -> [SegmentPart] {
        guard points.count >= 2 else { return [] }
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
        return parts
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
