import Foundation
import CoreLocation
import Observation
import Security

enum SpeedLimitSourceMode: String, CaseIterable, Identifiable {
    case current = "Current"
    case enhancedOSM = "Enhanced OSM"
    case here = "HERE"

    var id: String { rawValue }

    var shortDescription: String {
        switch self {
        case .current:
            return "Original decompiled HUDWAY OSM matcher"
        case .enhancedOSM:
            return "Enhanced OSM trace-aware matcher"
        case .here:
            return "HERE Route Matching + applicable speed limit"
        }
    }
}

enum HereAPIKeyStore {
    private static let service = "com.jjunnyy.hudcontroller.here"
    private static let account = "route-matching-api-key"

    static func save(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
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
        let oneway: String?
        let name: String?
        let ref: String?

        enum CodingKeys: String, CodingKey {
            case highway
            case maxspeed
            case maxspeedForward = "maxspeed:forward"
            case maxspeedBackward = "maxspeed:backward"
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
        let parts: [SegmentPart]
    }

    struct EnhancedCandidate {
        let elementID: Int64
        let speedMph: Int
        let score: Double
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
    private var hereTrace: [CLLocation] = []
    private var hereLimitMph: Int?
    private var hereLimitUpdatedAt: Date?
    private var lastHereRequestAt: Date?
    private var lastHereRequestLocation: CLLocation?

    private(set) var currentSpeedMph = 0
    private(set) var currentSpeedLimitMph = 0
    private(set) var status = "Waiting for location"
    private(set) var sourceDetail = "Current • original matcher"

    var hereAPIKeyDraft: String = HereAPIKeyStore.load() ?? ""

    var sourceMode: SpeedLimitSourceMode {
        didSet {
            UserDefaults.standard.set(sourceMode.rawValue, forKey: "HUD.Speed.limitSource")
            resetProviderStateForSourceChange()
            if enabled { refreshNow() }
        }
    }

    var hereAPIKeyConfigured: Bool {
        !(HereAPIKeyStore.load()?.isEmpty ?? true)
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

    func saveHereAPIKey() {
        let trimmed = hereAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            status = "HERE API key is empty"
            return
        }
        HereAPIKeyStore.save(trimmed)
        hereAPIKeyDraft = trimmed
        status = "HERE API key saved securely"
        logger.log("SPEED LIMIT", "HERE API key saved to Keychain")
        if sourceMode == .here {
            refreshNow()
        }
    }

    func clearHereAPIKey() {
        HereAPIKeyStore.clear()
        hereAPIKeyDraft = ""
        hereLimitMph = nil
        hereLimitUpdatedAt = nil
        status = "HERE API key removed"
        logger.log("SPEED LIMIT", "HERE API key removed from Keychain")
    }

    func start() {
        logger.log("SPEED", "Starting original-style GPS + OSM speed engine")
        logger.log("SPEED LIMIT", "Selected source = \(sourceMode.rawValue)")
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
            lastHereRequestAt = nil
            lastHereRequestLocation = nil
            Task { await updateProviderDataIfNeeded(at: location, force: true) }
        }
    }

    private func resetProviderStateForSourceChange() {
        segments.removeAll()
        enhancedSegments.removeAll()
        enhancedCurrentSegmentID = nil
        enhancedPendingCandidate = nil
        hereLimitMph = nil
        hereLimitUpdatedAt = nil
        hereTrace.removeAll()
        lastQueryLocation = nil
        lastHereRequestAt = nil
        lastHereRequestLocation = nil
        requestInFlight = false
        currentSpeedLimitMph = 0
        lastSentLimit = -1
        sourceDetail = "\(sourceMode.rawValue) • waiting for data"

        if bluetooth.state == .connected, showSpeedLimit {
            bluetooth.enqueue(
                HudCommands.speedLimit(limit: 0, tolerance: 0),
                label: "Speed-limit source changed → clear stale sign"
            )
        }
        logger.log("SPEED LIMIT", "Speed-limit source changed to \(sourceMode.rawValue)")
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

        appendHereTrace(location)

        let limit: Int?
        switch sourceMode {
        case .current:
            limit = bestSpeedLimit(at: location)
            sourceDetail = "Current • original OSM"
        case .enhancedOSM:
            limit = bestEnhancedSpeedLimit(at: location)
            sourceDetail = "Enhanced OSM • trace/continuity"
        case .here:
            if let updatedAt = hereLimitUpdatedAt,
               Date().timeIntervalSince(updatedAt) <= 30 {
                limit = hereLimitMph
            } else {
                limit = nil
            }
            sourceDetail = hereAPIKeyConfigured
                ? "HERE • route matching"
                : "HERE • API key required"
        }

        if let limit, limit > 0 {
            applyResolvedLimit(limit)
            status = "\(sourceMode.rawValue) • GPS \(currentSpeedMph) mph • limit \(limit) mph"
        } else {
            status = sourceMode == .here && !hereAPIKeyConfigured
                ? "HERE selected • save an API key to begin testing"
                : "\(sourceMode.rawValue) • GPS \(currentSpeedMph) mph • finding speed limit…"
        }

        Task { await updateProviderDataIfNeeded(at: location, force: false) }
    }

    private func applyResolvedLimit(_ limit: Int) {
        currentSpeedLimitMph = limit
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

    private func updateProviderDataIfNeeded(at location: CLLocation, force: Bool) async {
        switch sourceMode {
        case .current:
            await updateOriginalSegmentsIfNeeded(at: location, force: force)
        case .enhancedOSM:
            await updateEnhancedSegmentsIfNeeded(at: location, force: force)
        case .here:
            await updateHereLimitIfNeeded(at: location, force: force)
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
                "Enhanced OSM matcher loaded \(newSegments.count) roads (500m query / directional maxspeed / continuity score)"
            )
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

                let kmh: Int?
                if travelingForward {
                    kmh = segment.forwardKmh ?? segment.baseKmh ?? segment.backwardKmh
                } else {
                    kmh = segment.backwardKmh ?? segment.baseKmh ?? segment.forwardKmh
                }
                guard let kmh, kmh > 0 else { continue }

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

    // MARK: - HERE route matching test source

    private func appendHereTrace(_ location: CLLocation) {
        if let last = hereTrace.last, last.distance(from: location) < 5 {
            return
        }
        hereTrace.append(location)
        if hereTrace.count > 12 {
            hereTrace.removeFirst(hereTrace.count - 12)
        }
    }

    private func updateHereLimitIfNeeded(at location: CLLocation, force: Bool) async {
        guard let apiKey = HereAPIKeyStore.load(), !apiKey.isEmpty else {
            status = "HERE selected • save an API key to begin testing"
            return
        }

        if !force {
            if let lastHereRequestAt, Date().timeIntervalSince(lastHereRequestAt) < 8 {
                return
            }
            if let lastHereRequestLocation,
               lastHereRequestLocation.distance(from: location) < 35,
               let updatedAt = hereLimitUpdatedAt,
               Date().timeIntervalSince(updatedAt) < 15 {
                return
            }
        }

        guard hereTrace.count >= 2 else {
            status = "HERE selected • collecting GPS trace…"
            return
        }
        guard !requestInFlight else { return }
        requestInFlight = true
        defer { requestInFlight = false }

        guard var comps = URLComponents(
            string: "https://routematching.hereapi.com/v8/match/routelinks"
        ) else { return }
        comps.queryItems = [
            URLQueryItem(name: "routeMatch", value: "1"),
            URLQueryItem(name: "mode", value: "fastest;car;traffic:disabled"),
            URLQueryItem(name: "attributes", value: "APPLICABLE_SPEED_LIMIT(*)"),
            URLQueryItem(name: "apiKey", value: apiKey)
        ]
        guard let url = comps.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        var csv = "LATITUDE,LONGITUDE,TIMESTAMP\n"
        let formatter = ISO8601DateFormatter()
        for point in hereTrace {
            csv += "\(point.coordinate.latitude),\(point.coordinate.longitude),\(formatter.string(from: point.timestamp))\n"
        }
        request.httpBody = csv.data(using: .utf8)

        do {
            lastHereRequestAt = Date()
            lastHereRequestLocation = location
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
                throw NSError(
                    domain: "HERE",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) \(body)"]
                )
            }

            let object = try JSONSerialization.jsonObject(with: data)
            let limits = Self.extractHereApplicableSpeedLimits(from: object)
            guard let limit = limits.last, limit > 0 else {
                throw NSError(
                    domain: "HERE",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No applicable speed limit in route-match response"]
                )
            }

            guard sourceMode == .here else {
                logger.log("SPEED LIMIT", "Discarded stale HERE response after source switch")
                return
            }
            hereLimitMph = limit
            hereLimitUpdatedAt = Date()
            applyResolvedLimit(limit)
            status = "HERE • GPS \(currentSpeedMph) mph • limit \(limit) mph"
            logger.log(
                "SPEED LIMIT",
                "HERE route match resolved \(limit) mph from \(hereTrace.count)-point GPS trace"
            )
        } catch {
            logger.log("SPEED LIMIT ERROR", "HERE: \(error.localizedDescription)")
            status = "HERE lookup failed • \(error.localizedDescription)"
        }
    }

    private static func extractHereApplicableSpeedLimits(from object: Any) -> [Int] {
        var result: [Int] = []

        func numericValue(_ value: Any?) -> Double? {
            if let n = value as? NSNumber { return n.doubleValue }
            if let s = value as? String { return Double(s) }
            return nil
        }

        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let raw = numericValue(dict["APPLICABLE_SPEED_LIMIT"]), raw > 0 {
                    let unit = (dict["SPEED_LIMIT_UNIT"] as? String ?? "K").uppercased()
                    let mph: Int
                    if unit.hasPrefix("M") {
                        mph = Int(raw.rounded())
                    } else {
                        mph = Int((raw / 1.609344).rounded())
                    }
                    if mph > 0 { result.append(mph) }
                }
                for child in dict.values { walk(child) }
            } else if let array = value as? [Any] {
                for child in array { walk(child) }
            }
        }

        walk(object)
        return result
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
