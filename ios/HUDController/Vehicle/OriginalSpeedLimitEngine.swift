import Foundation
import CoreLocation
import Observation

enum SpeedLimitSourceMode: String, CaseIterable, Identifiable {
    case current = "Current"
    case traceOSM = "OSM Trace"
    case improvedTracePhilly = "Improved + Philly GIS"

    var id: String { rawValue }

    var shortDescription: String {
        switch self {
        case .current:
            return "Original decompiled HUDWAY OSM matcher"
        case .traceOSM:
            return "Current rolling GPS-trace matcher using explicit OSM speed tags"
        case .improvedTracePhilly:
            return "Improved all-road trace matcher + Philadelphia Street Centerline speed GIS"
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

    struct ImprovedOSMSegment {
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

    struct PhiladelphiaSpeedSegment {
        let objectID: Int
        let name: String?
        let speedMph: Int
        let residentialLayer: Bool
        /// False only when the Residential Streets layer had no valid numeric
        /// speed and we filled 25 mph from the ordinary Philadelphia local-road
        /// default. Inferred values may be displayed but must not arm warnings.
        let speedWasExplicit: Bool
        let parts: [SegmentPart]
    }

    private struct PhiladelphiaFetchResult {
        let segments: [PhiladelphiaSpeedSegment]
        let rawFeatures: Int
        let featuresWithSpeed: Int
        let featuresWithGeometry: Int
    }

    private struct TraceGeometryMatch {
        let score: Double
        let currentDistance: Double
        let currentAngle: Double
        let matchedPoints: Int
        let forward: Bool
        let nearestStart: CLLocationCoordinate2D
        let nearestEnd: CLLocationCoordinate2D
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
    /// True only when the current GPS sample is genuinely resolved against an
    /// eligible OSM Trace candidate. Holding the prior displayed sign for visual
    /// continuity must not refresh overspeed-warning freshness.
    private var traceLastResolutionFresh = false


    // v90.18 improved source keeps its own caches/state so the current OSM Trace
    // mode remains an unchanged A/B comparison path.
    private var improvedSegments: [ImprovedOSMSegment] = []
    private var improvedLastQueryLocation: CLLocation?
    private var improvedRequestInFlight = false
    private var improvedLastFailureAt: Date?
    private var improvedCurrentRoadID: Int64?
    /// Stable semantic identity for the currently confirmed OSM road. OSM commonly
    /// splits one physical street into many way IDs; v90.22 uses normalized name/ref
    /// identity to hand off between those pieces without blanking an unchanged sign.
    private var improvedCurrentRoadIdentity: String?
    private var improvedPendingRoad: (id: Int64, count: Int)?
    private var improvedLastConfidenceMargin: Double = 0
    private var improvedLastResolutionFresh = false
    private var improvedLastResolutionWarningEligible = false
    /// Fresh display-only continuity can preserve the sign while road identity is
    /// still geometrically trustworthy or while an explicit same-limit successor is
    /// one confirmation sample away. Neither path refreshes warning eligibility.
    private var improvedDisplayContinuityFresh = false
    private var improvedDisplayContinuityReason = "none"
    private var improvedResolutionSource = "none"
    private var improvedPendingLimit: (key: String, mph: Int, count: Int, source: String)?
    /// The displayed speed may only be propagated across same-road untagged pieces
    /// when it was actually established for the current road identity. A hard turn
    /// onto a different road disarms inherited continuity until the new road gets a
    /// fresh explicit/GIS/corridor-consensus limit.
    private var improvedSameRoadContinuityArmed = true

    // v90.27 bounded same-road display cache. A limit that was freshly established
    // for the current semantic road may survive short OSM/cache holes while GPS
    // trajectory remains compatible with that same road. Cached holds are always
    // display-only: they never refresh warning eligibility.
    private var improvedRoadLimitCacheIdentity: String?
    private var improvedRoadLimitCacheMph = 0
    private var improvedRoadLimitCacheSupportedAt: Date?
    private var improvedRoadLimitCacheLocation: CLLocation?
    private var improvedRoadLimitCacheCourse: CLLocationDirection = -1
    private var improvedLatestLocation: CLLocation?
    private let improvedRoadLimitCacheMaxAgeSeconds: TimeInterval = 90.0
    private let improvedRoadLimitCacheMaxDistanceMeters: CLLocationDistance = 1_200
    private let improvedRoadLimitCacheMaxCourseDeltaDegrees: Double = 35.0

    private var philadelphiaSpeedSegments: [PhiladelphiaSpeedSegment] = []
    private var philadelphiaLastQueryLocation: CLLocation?
    private var philadelphiaRequestInFlight = false
    private var philadelphiaLastFailureAt: Date?
    private var philadelphiaDatasetAvailable = false
    private let providerFailureRetrySeconds: TimeInterval = 12.0
    private let improvedDisplayGraceSeconds: TimeInterval = 4.0

    private(set) var currentSpeedMph = 0
    private(set) var currentSpeedLimitMph = 0
    /// Warning eligibility is intentionally stricter than merely having a cached
    /// integer limit. A previous-drive UserDefaults value must never arm a red-light
    /// warning before the currently selected matcher has resolved a live road limit.
    private(set) var speedLimitAvailableForWarning = false
    /// The currently displayed limit may be useful even when it came from a
    /// lower-confidence residential fallback. Warning eligibility is tracked
    /// separately so inferred display values cannot arm HUD/ambient warnings.
    private var currentLimitWarningEligible = false
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
            if showSpeedLimit {
                resendCurrentLimitIfPossible()
            } else if bluetooth.state == .connected {
                bluetooth.enqueue(
                    HudCommands.speedLimit(limit: 0, tolerance: 0),
                    label: "Speed-limit sign disabled → clear sign"
                )
                bluetooth.enqueue(
                    HudCommands.speedWarningThreshold(0),
                    label: "Speed-limit sign disabled → native warning OFF"
                )
            }
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
        let storedSource = d.string(forKey: "HUD.Speed.limitSource") ?? ""
        // v90.18 removes the obsolete Enhanced OSM UI mode. Existing installs that
        // had selected it migrate to the current OSM Trace comparison mode.
        if storedSource == "Enhanced OSM" {
            self.sourceMode = .traceOSM
        } else if storedSource == "Improved Trace + Philly GIS" {
            // Migration from the short-lived development label used before v90.18.
            self.sourceMode = .improvedTracePhilly
        } else {
            self.sourceMode = SpeedLimitSourceMode(rawValue: storedSource) ?? .current
        }

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
        currentLimitWarningEligible = false
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
        currentLimitWarningEligible = false
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
        bluetooth.enqueue(
            HudCommands.speedWarningThreshold(0),
            label: "Speed-limit session prime → native warning OFF until fresh limit"
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
        if currentLimitWarningEligible {
            sendOriginalAutomaticSpeedWarning(legalLimitMph: currentSpeedLimitMph)
        } else {
            bluetooth.enqueue(
                HudCommands.speedWarningThreshold(0),
                label: "Displayed limit is not warning-eligible → native warning OFF"
            )
        }
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
        traceLastResolutionFresh = false
        improvedSegments.removeAll()
        improvedLastQueryLocation = nil
        improvedRequestInFlight = false
        improvedLastFailureAt = nil
        improvedCurrentRoadID = nil
        improvedCurrentRoadIdentity = nil
        improvedRoadLimitCacheIdentity = nil
        improvedRoadLimitCacheMph = 0
        improvedRoadLimitCacheSupportedAt = nil
        improvedRoadLimitCacheLocation = nil
        improvedRoadLimitCacheCourse = -1
        improvedLatestLocation = nil
        improvedPendingRoad = nil
        improvedLastConfidenceMargin = 0
        improvedLastResolutionFresh = false
        improvedLastResolutionWarningEligible = false
        improvedDisplayContinuityFresh = false
        improvedDisplayContinuityReason = "none"
        improvedResolutionSource = "none"
        improvedPendingLimit = nil
        improvedSameRoadContinuityArmed = true
        philadelphiaSpeedSegments.removeAll()
        philadelphiaLastQueryLocation = nil
        philadelphiaRequestInFlight = false
        philadelphiaLastFailureAt = nil
        philadelphiaDatasetAvailable = false
        lastQueryLocation = nil
        requestInFlight = false
        currentSpeedLimitMph = 0
        currentLimitWarningEligible = false
        lastResolvedLimitAt = nil
        speedLimitAvailableForWarning = false
        lastSentLimit = -1
        sourceDetail = "\(sourceMode.rawValue) • waiting for data"

        if bluetooth.state == .connected, showSpeedLimit {
            bluetooth.enqueue(
                HudCommands.speedLimit(limit: 0, tolerance: 0),
                label: "Speed-limit source changed → clear stale sign"
            )
            bluetooth.enqueue(
                HudCommands.speedWarningThreshold(0),
                label: "Speed-limit source changed → native warning OFF until fresh limit"
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
                    format: "gps=%.6f,%.6f resolved=%@ fresh=%d currentWay=%@ pending=%@ margin=%.2f",
                    location.coordinate.latitude,
                    location.coordinate.longitude,
                    limit.map { "\($0)mph" } ?? "none",
                    traceLastResolutionFresh ? 1 : 0,
                    traceCurrentSegmentID.map { String($0) } ?? "none",
                    tracePendingCandidate.map { "\($0.id):\($0.mph)mph#\($0.count)" } ?? "none",
                    traceLastConfidenceMargin
                )
            )
            sourceDetail = String(
                format: "OSM Trace • rolling trace • margin %.2f",
                traceLastConfidenceMargin
            )
        case .improvedTracePhilly:
            logger.log(
                "IMPROVED TRACE GPS",
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
            limit = bestImprovedTraceSpeedLimit(at: location)
            logger.log(
                "IMPROVED TRACE OUTPUT",
                String(
                    format: "gps=%.6f,%.6f resolved=%@ fresh=%d displayContinuity=%d road=%@ source=%@ margin=%.2f phillyData=%d",
                    location.coordinate.latitude,
                    location.coordinate.longitude,
                    limit.map { "\($0)mph" } ?? "none",
                    improvedLastResolutionFresh ? 1 : 0,
                    improvedDisplayContinuityFresh ? 1 : 0,
                    improvedCurrentRoadID.map { String($0) } ?? "none",
                    improvedResolutionSource,
                    improvedLastConfidenceMargin,
                    philadelphiaDatasetAvailable ? 1 : 0
                )
            )
            sourceDetail = String(
                format: "Improved Trace • %@ • margin %.2f",
                improvedResolutionSource,
                improvedLastConfidenceMargin
            )
        }

        if let limit, limit > 0 {
            let resolutionIsFresh: Bool
            switch sourceMode {
            case .traceOSM:
                resolutionIsFresh = traceLastResolutionFresh
            case .improvedTracePhilly:
                resolutionIsFresh = improvedLastResolutionFresh
            case .current:
                resolutionIsFresh = true
            }
            if resolutionIsFresh {
                let warningEligible = sourceMode == .improvedTracePhilly
                    ? improvedLastResolutionWarningEligible
                    : true
                applyResolvedLimit(limit, warningEligible: warningEligible)
            }
            status = resolutionIsFresh
                ? "\(sourceMode.rawValue) • GPS \(currentSpeedMph) mph • limit \(limit) mph"
                : "\(sourceMode.rawValue) • GPS \(currentSpeedMph) mph • holding prior limit \(limit) mph"
        } else {
            status = "\(sourceMode.rawValue) • GPS \(currentSpeedMph) mph • finding speed limit…"
        }

        if sourceMode == .improvedTracePhilly,
           !improvedLastResolutionFresh,
           !improvedDisplayContinuityFresh,
           currentSpeedLimitMph > 0,
           let lastResolvedLimitAt,
           Date().timeIntervalSince(lastResolvedLimitAt) > improvedDisplayGraceSeconds {
            clearDisplayedLimit(reason: "Improved Trace lost a fresh road match for >\(Int(improvedDisplayGraceSeconds))s")
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

    private func applyResolvedLimit(_ limit: Int, warningEligible: Bool = true) {
        let previousWarningEligible = currentLimitWarningEligible
        let limitChanged = limit != lastSentLimit
        currentSpeedLimitMph = limit
        currentLimitWarningEligible = warningEligible
        lastResolvedLimitAt = Date()
        speedLimitAvailableForWarning = showSpeedLimit && limit > 0 && warningEligible
        UserDefaults.standard.set(limit, forKey: "HUD.Speed.lastKnownLimitMph")

        if sourceMode == .improvedTracePhilly,
           warningEligible || improvedResolutionSource.contains("corridor consensus"),
           !improvedResolutionSource.contains("cached same-road"),
           let identity = improvedCurrentRoadIdentity,
           let location = improvedLatestLocation {
            improvedRoadLimitCacheIdentity = identity
            improvedRoadLimitCacheMph = limit
            improvedRoadLimitCacheSupportedAt = Date()
            improvedRoadLimitCacheLocation = location
            improvedRoadLimitCacheCourse = location.course
            logger.log(
                "IMPROVED TRACE DECISION",
                "same-road display cache refreshed identity=\(identity) limit=\(limit) source=\(improvedResolutionSource)"
            )
        }

        guard showSpeedLimit, bluetooth.state == .connected else { return }
        if limitChanged {
            lastSentLimit = limit
            bluetooth.enqueue(
                HudCommands.speedLimit(limit: limit, tolerance: 0),
                label: "Speed limit \(limit) mph (tolerance 0) source=\(sourceMode.rawValue)"
            )
        }

        // Warning eligibility can legitimately change while the displayed number
        // stays the same (for example inferred residential 25 -> explicit posted 25).
        // Keep the HUD firmware threshold synchronized with that confidence edge.
        if limitChanged || warningEligible != previousWarningEligible {
            if warningEligible {
                sendOriginalAutomaticSpeedWarning(legalLimitMph: limit)
            } else {
                bluetooth.enqueue(
                    HudCommands.speedWarningThreshold(0),
                    label: "Display-only inferred speed limit — disable native warning threshold"
                )
                logger.log("SPEED LIMIT", "Displayed \(limit) mph as lower-confidence inferred value; speed warnings disabled")
            }
        }
    }

    private func clearDisplayedLimit(reason: String) {
        guard currentSpeedLimitMph != 0 || lastSentLimit != 0 else { return }
        currentSpeedLimitMph = 0
        currentLimitWarningEligible = false
        lastResolvedLimitAt = nil
        speedLimitAvailableForWarning = false
        lastSentLimit = 0
        if showSpeedLimit, bluetooth.state == .connected {
            bluetooth.enqueue(
                HudCommands.speedLimit(limit: 0, tolerance: 0),
                label: "Clear stale speed-limit sign — \(reason)"
            )
            bluetooth.enqueue(
                HudCommands.speedWarningThreshold(0),
                label: "Clear stale speed-limit warning threshold — \(reason)"
            )
        }
        logger.log("SPEED LIMIT", "Cleared stale displayed limit: \(reason)")
        onSpeedStateChanged?(currentSpeedMph, 0, false)
    }

    private func refreshWarningLimitAvailability(now: Date) {
        guard showSpeedLimit,
              currentSpeedLimitMph > 0,
              currentLimitWarningEligible,
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
        case .traceOSM:
            await updateEnhancedSegmentsIfNeeded(at: location, force: force)
        case .improvedTracePhilly:
            async let osmUpdate: Void = updateImprovedSegmentsIfNeeded(at: location, force: force)
            async let phillyUpdate: Void = updatePhiladelphiaSpeedDataIfNeeded(at: location, force: force)
            _ = await (osmUpdate, phillyUpdate)
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
            self.logger.log("SPEED LIMIT ERROR", "OSM Trace: \(error.localizedDescription)")
            self.status = "OSM Trace lookup failed; GPS speed still active"
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
        traceLastResolutionFresh = false
        guard !enhancedSegments.isEmpty else {
            traceLastConfidenceMargin = 0
            logger.log("OSM TRACE MATCH", "no OSM road dataset loaded yet; waiting for 500m query")
            return nil
        }

        let trace = Array(traceLocations.suffix(8))
        guard !trace.isEmpty else {
            traceLastConfidenceMargin = 0
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
            traceLastConfidenceMargin = 0
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
            traceLastResolutionFresh = true
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
                    traceLastResolutionFresh = true
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

    // MARK: - v90.18 improved trace + Philadelphia public GIS

    private func updateImprovedSegmentsIfNeeded(at location: CLLocation, force: Bool) async {
        if !force, let improvedLastFailureAt,
           Date().timeIntervalSince(improvedLastFailureAt) < providerFailureRetrySeconds {
            return
        }
        if !force, let improvedLastQueryLocation,
           improvedLastQueryLocation.distance(from: location) <= 200 {
            return
        }
        guard !improvedRequestInFlight else { return }
        improvedRequestInFlight = true
        defer { improvedRequestInFlight = false }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        // Unlike the comparison OSM Trace mode, the improved source intentionally
        // loads drivable roads even when maxspeed is absent. This lets the geometry
        // matcher recognize a residential/local road instead of stealing the speed
        // tag from a nearby arterial or parallel expressway.
        let query = """
        [out:json];
        way[highway~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"](around:500,\(lat),\(lon));
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
            let roads = decoded.elements.compactMap(Self.makeImprovedSegment)
            improvedSegments = roads
            improvedLastQueryLocation = location
            improvedLastFailureAt = nil
            logger.log(
                "IMPROVED TRACE QUERY",
                String(format: "OSM center=%.6f,%.6f radius=500m allDrivableRoads=%d", lat, lon, roads.count)
            )
        } catch {
            improvedLastFailureAt = Date()
            logger.log("SPEED LIMIT ERROR", "Improved OSM Trace: \(error.localizedDescription); retry backoff=\(Int(providerFailureRetrySeconds))s")
            status = "Improved OSM lookup failed; GPS speed still active"
        }
    }

    private static func makeImprovedSegment(_ element: Element) -> ImprovedOSMSegment? {
        guard let tags = element.tags,
              let highway = tags.highway,
              let geometry = element.geometry,
              geometry.count >= 2 else { return nil }
        let points = geometry.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        return ImprovedOSMSegment(
            elementID: element.id,
            highway: highway,
            name: tags.name,
            reference: tags.ref,
            baseKmh: tags.maxspeed.flatMap { parseOriginalMaxSpeed($0)?.kmh },
            forwardKmh: tags.maxspeedForward.flatMap { parseOriginalMaxSpeed($0)?.kmh },
            backwardKmh: tags.maxspeedBackward.flatMap { parseOriginalMaxSpeed($0)?.kmh },
            baseConditional: tags.maxspeedConditional,
            forwardConditional: tags.maxspeedForwardConditional,
            backwardConditional: tags.maxspeedBackwardConditional,
            parts: makeParts(points)
        )
    }

    private func updatePhiladelphiaSpeedDataIfNeeded(at location: CLLocation, force: Bool) async {
        guard Self.isInsidePhiladelphiaCoverage(location.coordinate) else {
            philadelphiaSpeedSegments.removeAll()
            philadelphiaDatasetAvailable = false
            philadelphiaLastQueryLocation = nil
            philadelphiaLastFailureAt = nil
            return
        }
        if !force, let philadelphiaLastFailureAt,
           Date().timeIntervalSince(philadelphiaLastFailureAt) < providerFailureRetrySeconds {
            return
        }
        if !force, let philadelphiaLastQueryLocation,
           philadelphiaLastQueryLocation.distance(from: location) <= 200 {
            return
        }
        guard !philadelphiaRequestInFlight else { return }
        philadelphiaRequestInFlight = true
        defer { philadelphiaRequestInFlight = false }

        do {
            let result = try await fetchPhiladelphiaStreetCenterlines(at: location)
            philadelphiaSpeedSegments = result.segments
            philadelphiaDatasetAvailable = true
            philadelphiaLastQueryLocation = location
            philadelphiaLastFailureAt = nil
            logger.log(
                "PHILLY GIS QUERY",
                String(
                    format: "center=%.6f,%.6f pointRadius=650m rawFeatures=%d featuresWithSpeed=%d featuresWithGeometry=%d parsedSegments=%d layersOK=1/1",
                    location.coordinate.latitude,
                    location.coordinate.longitude,
                    result.rawFeatures,
                    result.featuresWithSpeed,
                    result.featuresWithGeometry,
                    result.segments.count
                )
            )
        } catch {
            philadelphiaSpeedSegments.removeAll()
            philadelphiaDatasetAvailable = false
            philadelphiaLastFailureAt = Date()
            logger.log(
                "PHILLY GIS ERROR",
                "Philadelphia Street Centerline failed: \(error.localizedDescription); retry backoff=\(Int(providerFailureRetrySeconds))s"
            )
        }
    }

    /// v90.26: use Philadelphia's current Street Centerline feature layer. The old
    /// SpeedLimits/FeatureServer service used by v90.18-v90.25 returned successful
    /// empty queries in the field. The maintained centerline schema exposes both
    /// POSTED_SPEED_LIMIT and SPEED_LIMIT directly on the street polylines.
    private func fetchPhiladelphiaStreetCenterlines(
        at location: CLLocation
    ) async throws -> PhiladelphiaFetchResult {
        let base = "https://services.arcgis.com/0L95CJ0VTaxqcmED/ArcGIS/rest/services/TRANSPORTATION_street_segment/FeatureServer/0/query"
        guard var comps = URLComponents(string: base) else { return PhiladelphiaFetchResult(segments: [], rawFeatures: 0, featuresWithSpeed: 0, featuresWithGeometry: 0) }

        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude

        // v90.28: use ArcGIS' point + distance query rather than a WGS84
        // envelope against a layer whose native spatial reference is EPSG:2277.
        // Field logs from v90.26/v90.27 showed successful HTTP responses but
        // rawFeatures=0 for every envelope query. Point+distance lets ArcGIS do
        // the projection internally and is the canonical proximity-query shape.
        comps.queryItems = [
            URLQueryItem(name: "f", value: "json"),
            URLQueryItem(name: "where", value: "BUILT_STATUS=2"),
            URLQueryItem(name: "geometry", value: String(format: "%.7f,%.7f", longitude, latitude)),
            URLQueryItem(name: "geometryType", value: "esriGeometryPoint"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "distance", value: "650"),
            URLQueryItem(name: "units", value: "esriSRUnit_Meter"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
            URLQueryItem(name: "outFields", value: "OBJECTID,SEGMENT_ID,FULL_STREET_NAME,STREET_NAME,SPEED_LIMIT,POSTED_SPEED_LIMIT,ROAD_CLASS,BUILT_STATUS"),
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "outSR", value: "4326")
        ]
        guard let url = comps.url else { return PhiladelphiaFetchResult(segments: [], rawFeatures: 0, featuresWithSpeed: 0, featuresWithGeometry: 0) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Self.parsePhiladelphiaSpeedFeatures(data)
    }


    // These helpers are intentionally nonisolated. OriginalSpeedLimitEngine is @MainActor,
    // while Sequence.compactMap executes its transform in a synchronous nonisolated context
    // under Swift 6 actor-isolation checking. Keeping pure JSON scalar parsing outside the
    // closure avoids an implicit cross-actor call during the Philadelphia GIS decode path.
    private nonisolated static func philadelphiaIntValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String {
            let digits = string.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int(digits)
        }
        return nil
    }

    private nonisolated static func philadelphiaValidSpeed(_ value: Any?) -> Int? {
        guard let speed = philadelphiaIntValue(value), (5...85).contains(speed) else { return nil }
        return speed
    }

    private static func parsePhiladelphiaSpeedFeatures(
        _ data: Data
    ) throws -> PhiladelphiaFetchResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PhiladelphiaFetchResult(segments: [], rawFeatures: 0, featuresWithSpeed: 0, featuresWithGeometry: 0)
        }
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Philadelphia GIS returned an error"
            throw NSError(domain: "PhiladelphiaSpeedGIS", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        guard let features = root["features"] as? [[String: Any]] else {
            return PhiladelphiaFetchResult(segments: [], rawFeatures: 0, featuresWithSpeed: 0, featuresWithGeometry: 0)
        }

        var featuresWithSpeed = 0
        var featuresWithGeometry = 0
        var parsed: [PhiladelphiaSpeedSegment] = []
        parsed.reserveCapacity(features.count)

        for feature in features {
            guard let attributes = feature["attributes"] as? [String: Any] else { continue }
            let explicitSpeed = Self.philadelphiaValidSpeed(attributes["POSTED_SPEED_LIMIT"])
                ?? Self.philadelphiaValidSpeed(attributes["SPEED_LIMIT"])
            if explicitSpeed != nil { featuresWithSpeed += 1 }

            guard let geometry = feature["geometry"] as? [String: Any],
                  let paths = geometry["paths"] as? [[[Double]]],
                  !paths.isEmpty else { continue }
            featuresWithGeometry += 1
            guard let speed = explicitSpeed else { continue }

            var parts: [SegmentPart] = []
            for path in paths {
                let points = path.compactMap { pair -> CLLocationCoordinate2D? in
                    guard pair.count >= 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                }
                parts.append(contentsOf: makeParts(points))
            }
            guard !parts.isEmpty else { continue }

            let objectID = Self.philadelphiaIntValue(attributes["OBJECTID"])
                ?? Self.philadelphiaIntValue(attributes["SEGMENT_ID"])
                ?? 0
            let name = (attributes["FULL_STREET_NAME"] as? String)
                ?? (attributes["STREET_NAME"] as? String)
            parsed.append(
                PhiladelphiaSpeedSegment(
                    objectID: objectID,
                    name: name,
                    speedMph: speed,
                    residentialLayer: false,
                    speedWasExplicit: true,
                    parts: parts
                )
            )
        }

        return PhiladelphiaFetchResult(
            segments: parsed,
            rawFeatures: features.count,
            featuresWithSpeed: featuresWithSpeed,
            featuresWithGeometry: featuresWithGeometry
        )
    }

    private static func isInsidePhiladelphiaCoverage(_ coordinate: CLLocationCoordinate2D) -> Bool {
        // Loose city envelope only controls whether the optional public GIS is queried;
        // it is not used to infer a speed limit.
        (39.85...40.15).contains(coordinate.latitude)
            && (-75.30 ... -74.95).contains(coordinate.longitude)
    }

    private func traceGeometryMatch(
        parts: [SegmentPart],
        trace: [CLLocation],
        location: CLLocation,
        continuityBonus: Double = 0
    ) -> TraceGeometryMatch? {
        guard !parts.isEmpty, !trace.isEmpty else { return nil }
        let fallbackCourse = trace.reversed().first(where: { $0.course >= 0 })?.course ?? 0
        let currentCourse = location.course >= 0 ? location.course : fallbackCourse
        var currentBest: (
            distance: Double,
            angle: Double,
            forward: Bool,
            start: CLLocationCoordinate2D,
            end: CLLocationCoordinate2D
        )?
        for part in parts {
            let distance = Self.distanceFrom(location.coordinate, toSegmentA: part.start, b: part.end)
            let forwardAngle = Self.angularDifference(part.direction, currentCourse)
            let reverseAngle = Self.angularDifference(fmod(part.direction + 180, 360), currentCourse)
            let forward = forwardAngle <= reverseAngle
            let angle = min(forwardAngle, reverseAngle)
            if currentBest == nil
                || distance + angle * 0.15 < currentBest!.distance + currentBest!.angle * 0.15 {
                currentBest = (distance, angle, forward, part.start, part.end)
            }
        }
        guard let currentBest, currentBest.distance <= 60, currentBest.angle <= 105 else { return nil }

        var weightedScore = 0.0
        var totalWeight = 0.0
        var matchedPoints = 0
        for (index, sample) in trace.enumerated() {
            let weight = Double(index + 1)
            let sampleCourse = sample.course >= 0 ? sample.course : currentCourse
            var pointBest: Double?
            for part in parts {
                let distance = Self.distanceFrom(sample.coordinate, toSegmentA: part.start, b: part.end)
                guard distance <= 85 else { continue }
                let forwardAngle = Self.angularDifference(part.direction, sampleCourse)
                let reverseAngle = Self.angularDifference(fmod(part.direction + 180, 360), sampleCourse)
                let angle = min(forwardAngle, reverseAngle)
                let candidate = min(4.0, distance / 18.0) + min(3.0, angle / 35.0)
                pointBest = min(pointBest ?? candidate, candidate)
            }
            if let pointBest {
                matchedPoints += 1
                weightedScore += pointBest * weight
            } else {
                weightedScore += 7.0 * weight
            }
            totalWeight += weight
        }
        guard matchedPoints >= max(1, trace.count / 2) else { return nil }
        return TraceGeometryMatch(
            score: weightedScore / max(1.0, totalWeight) + continuityBonus,
            currentDistance: currentBest.distance,
            currentAngle: currentBest.angle,
            matchedPoints: matchedPoints,
            forward: currentBest.forward,
            nearestStart: currentBest.start,
            nearestEnd: currentBest.end
        )
    }

    /// OSM way IDs are implementation details, not road identities. Normalize the
    /// human-facing name first (or ref when unnamed) so adjacent pieces of the same
    /// street can hand off without a false stale-sign interval.
    private static func normalizedRoadIdentity(name: String?, reference: String?) -> String? {
        func normalize(_ raw: String) -> String {
            let aliases: [String: String] = [
                "jr": "junior", "dr": "drive", "rd": "road", "st": "street",
                "ave": "avenue", "av": "avenue", "blvd": "boulevard",
                "hwy": "highway", "pkwy": "parkway"
            ]
            return raw
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .map { aliases[$0] ?? $0 }
                .joined(separator: " ")
        }

        if let name {
            let normalized = normalize(name)
            if !normalized.isEmpty { return "name:\(normalized)" }
        }
        if let reference {
            let normalized = normalize(reference)
            if !normalized.isEmpty { return "ref:\(normalized)" }
        }
        return nil
    }

    /// Return a static, direction-independent explicit speed only when an OSM way
    /// is internally unambiguous. Directional or conditional conflicts are excluded
    /// from road-level inference and remain eligible only for direct local matching.
    private static func unambiguousStaticOSMSpeedMph(_ segment: ImprovedOSMSegment) -> Int? {
        if segment.baseConditional != nil || segment.forwardConditional != nil || segment.backwardConditional != nil {
            return nil
        }
        let values = [segment.baseKmh, segment.forwardKmh, segment.backwardKmh].compactMap { $0 }
        guard !values.isEmpty, Set(values).count == 1, let kmh = values.first else { return nil }
        return Int((Double(kmh) / 1.609344).rounded())
    }

    private static func minimumDistance(
        from coordinate: CLLocationCoordinate2D,
        to parts: [SegmentPart]
    ) -> Double {
        parts.map { part in
            distanceFrom(coordinate, toSegmentA: part.start, b: part.end)
        }.min() ?? 999_999
    }

    /// v90.26 road-level inference for an untagged current OSM piece. Only explicit,
    /// static speed tags on the exact same normalized road identity are considered.
    /// At least two nearby tagged ways must agree unanimously; conflicting speeds
    /// (for example a road that changes from 30 to 25) disable the inference.
    private func sameRoadOSMSpeedConsensus(
        identity: String,
        at location: CLLocation
    ) -> (mph: Int, count: Int, nearestMeters: Double)? {
        let observations: [(mph: Int, distance: Double)] = improvedSegments.compactMap { segment in
            guard Self.normalizedRoadIdentity(name: segment.name, reference: segment.reference) == identity,
                  let mph = Self.unambiguousStaticOSMSpeedMph(segment) else { return nil }
            let distance = Self.minimumDistance(from: location.coordinate, to: segment.parts)
            guard distance <= 650 else { return nil }
            return (mph, distance)
        }
        guard observations.count >= 2 else { return nil }
        let values = Set(observations.map(\.mph))
        guard values.count == 1, let mph = values.first else {
            if observations.count >= 2 {
                let speeds = values.sorted().map(String.init).joined(separator: ",")
                logger.log("IMPROVED TRACE DECISION", "same-road corridor consensus withheld identity=\(identity) conflicting=\(speeds)")
            }
            return nil
        }
        return (mph, observations.count, observations.map(\.distance).min() ?? 999)
    }

    private func bestImprovedTraceSpeedLimit(at location: CLLocation) -> Int? {
        improvedLatestLocation = location
        improvedLastResolutionFresh = false
        improvedLastResolutionWarningEligible = false
        improvedDisplayContinuityFresh = false
        improvedDisplayContinuityReason = "none"
        let trace = Array(traceLocations.suffix(8))
        guard !trace.isEmpty else { return nil }

        struct OSMScored {
            let segment: ImprovedOSMSegment
            let match: TraceGeometryMatch
            let speedMph: Int?
        }
        var osmScored: [OSMScored] = []
        for segment in improvedSegments {
            let continuity: Double
            if segment.elementID == improvedCurrentRoadID {
                continuity = -1.05
            } else if let pending = improvedPendingRoad, pending.id == segment.elementID {
                continuity = -0.25
            } else {
                continuity = 0
            }
            guard let match = traceGeometryMatch(
                parts: segment.parts,
                trace: trace,
                location: location,
                continuityBonus: continuity
            ) else { continue }
            let kmh = Self.resolvedKmh(for: segment, travelingForward: match.forward, at: location.timestamp)
            let mph = kmh.map { Int((Double($0) / 1.609344).rounded()) }
            osmScored.append(OSMScored(segment: segment, match: match, speedMph: mph))
        }
        osmScored.sort { $0.match.score < $1.match.score }

        let tracePoints = trace.map { sample in
            String(
                format: "%.6f,%.6f,c=%.0f,a=%.0f",
                sample.coordinate.latitude,
                sample.coordinate.longitude,
                sample.course,
                sample.horizontalAccuracy
            )
        }.joined(separator: ";")
        logger.log("IMPROVED TRACE PATH", "points=[\(tracePoints)]")

        var confirmedOSM: OSMScored?
        if let best = osmScored.first {
            let secondScore = osmScored.dropFirst().first?.match.score ?? (best.match.score + 3.0)
            let margin = max(0, secondScore - best.match.score)
            improvedLastConfidenceMargin = margin
            let summary = osmScored.prefix(5).map { item in
                let name = (item.segment.name ?? "-").replacingOccurrences(of: "|", with: "/")
                let ref = (item.segment.reference ?? "-").replacingOccurrences(of: "|", with: "/")
                return String(
                    format: "way=%lld name=%@ ref=%@ highway=%@ limit=%@ score=%.2f dist=%.1fm angle=%.1f matched=%d/%d seg=%.6f,%.6f>%.6f,%.6f speedTags=%@/%@/%@",
                    item.segment.elementID,
                    name,
                    ref,
                    item.segment.highway,
                    item.speedMph.map { "\($0)" } ?? "-",
                    item.match.score,
                    item.match.currentDistance,
                    item.match.currentAngle,
                    item.match.matchedPoints,
                    trace.count,
                    item.match.nearestStart.latitude,
                    item.match.nearestStart.longitude,
                    item.match.nearestEnd.latitude,
                    item.match.nearestEnd.longitude,
                    item.segment.baseKmh.map(String.init) ?? "-",
                    item.segment.forwardKmh.map(String.init) ?? "-",
                    item.segment.backwardKmh.map(String.init) ?? "-"
                )
            }.joined(separator: " | ")
            logger.log(
                "IMPROVED TRACE OSM MATCH",
                "currentWay=\(improvedCurrentRoadID.map(String.init) ?? "none") pending=\(improvedPendingRoad.map { "\($0.id)#\($0.count)" } ?? "none") top=[\(summary)]"
            )

            if improvedCurrentRoadIdentity == nil, let currentID = improvedCurrentRoadID,
               let currentSegment = improvedSegments.first(where: { $0.elementID == currentID }) {
                improvedCurrentRoadIdentity = Self.normalizedRoadIdentity(
                    name: currentSegment.name,
                    reference: currentSegment.reference
                )
            }

            // v90.26 completed-turn takeover. Rolling-trace history intentionally
            // favors the previous road, but after a real 90-degree turn that inertia
            // can hold the old way for many blocks. Use current-sample geometry to
            // hand road identity to a very close, well-aligned different street as
            // soon as the previous road is clearly behind/perpendicular.
            var hardRoadTakeover: OSMScored?
            if let currentID = improvedCurrentRoadID,
               let currentIdentity = improvedCurrentRoadIdentity,
               location.speed >= 1.5 {
                let currentCandidate = osmScored.first(where: { $0.segment.elementID == currentID })
                let currentLooksDeparted = currentCandidate == nil ||
                    currentCandidate!.match.currentDistance >= 18 ||
                    currentCandidate!.match.currentAngle >= 45
                if currentLooksDeparted {
                    hardRoadTakeover = osmScored
                        .filter { item in
                            item.segment.elementID != currentID &&
                            Self.normalizedRoadIdentity(name: item.segment.name, reference: item.segment.reference) != nil &&
                            Self.normalizedRoadIdentity(name: item.segment.name, reference: item.segment.reference) != currentIdentity &&
                            item.match.currentDistance <= 12 &&
                            item.match.currentAngle <= 20 &&
                            item.match.matchedPoints >= max(4, trace.count / 2) &&
                            item.match.score <= 3.25
                        }
                        .min { lhs, rhs in
                            lhs.match.currentDistance + lhs.match.currentAngle * 0.20 <
                                rhs.match.currentDistance + rhs.match.currentAngle * 0.20
                        }
                }
            }

            if let takeover = hardRoadTakeover {
                let previousID = improvedCurrentRoadID
                let previousIdentity = improvedCurrentRoadIdentity ?? "none"
                improvedCurrentRoadID = takeover.segment.elementID
                improvedCurrentRoadIdentity = Self.normalizedRoadIdentity(
                    name: takeover.segment.name,
                    reference: takeover.segment.reference
                )
                if improvedRoadLimitCacheIdentity != improvedCurrentRoadIdentity {
                    improvedRoadLimitCacheIdentity = nil
                    improvedRoadLimitCacheMph = 0
                    improvedRoadLimitCacheSupportedAt = nil
                    improvedRoadLimitCacheLocation = nil
                    improvedRoadLimitCacheCourse = -1
                }
                improvedPendingRoad = nil
                improvedPendingLimit = nil
                improvedSameRoadContinuityArmed = false
                currentLimitWarningEligible = false
                speedLimitAvailableForWarning = false
                confirmedOSM = takeover
                logger.log(
                    "IMPROVED TRACE DECISION",
                    String(
                        format: "completed-turn road takeover %lld(%@) → %lld(%@) dist=%.1fm angle=%.1f matched=%d/%d; inherited continuity disarmed",
                        previousID ?? 0,
                        previousIdentity,
                        takeover.segment.elementID,
                        improvedCurrentRoadIdentity ?? "-",
                        takeover.match.currentDistance,
                        takeover.match.currentAngle,
                        takeover.match.matchedPoints,
                        trace.count
                    )
                )
            }

            // v90.22 same-road fast handoff. A single physical street such as
            // Martin Luther King Junior Drive is split into many OSM ways. At those
            // boundaries a nearby service/link way can briefly win first place and
            // start the old 4-s stale countdown even while another excellent trace
            // candidate is the same named road with the same explicit 25-mph limit.
            // Prefer that semantic continuity before considering a different road.
            var sameRoadExplicit: OSMScored?
            var sameRoadUntagged: OSMScored?
            var sameRoadSuccessorIDs = Set<Int64>()
            if hardRoadTakeover == nil,
               improvedSameRoadContinuityArmed,
               let identity = improvedCurrentRoadIdentity,
               currentSpeedLimitMph > 0 {
                let sameIdentityCandidates = osmScored.filter { item in
                    Self.normalizedRoadIdentity(name: item.segment.name, reference: item.segment.reference) == identity
                }
                let strongSameRoadCandidates = sameIdentityCandidates.filter { item in
                    item.match.currentDistance <= 35 &&
                    item.match.currentAngle <= 35 &&
                    item.match.matchedPoints >= max(1, trace.count - 1) &&
                    item.match.score <= min(2.5, best.match.score + 0.75)
                }

                // v90.25 forward-successor escape hatch. The continuity bonus can
                // keep an aging current OSM way ranked first for one sample even
                // after the car has physically entered the next piece of the same
                // named street. Admit a very close/aligned same-road successor even
                // when it narrowly misses the old best+0.75 score gate. This fixes
                // the field-observed MLK dropout where the old way was ~40 m away
                // while the next MLK way was <5 m away and matched 8/8 trace points.
                let successorCandidates = sameIdentityCandidates.filter { item in
                    item.segment.elementID != improvedCurrentRoadID &&
                    item.match.currentDistance <= 20 &&
                    item.match.currentAngle <= 20 &&
                    item.match.matchedPoints >= max(1, trace.count - 1) &&
                    item.match.score <= min(2.75, best.match.score + 1.25)
                }
                sameRoadSuccessorIDs = Set(successorCandidates.map { $0.segment.elementID })

                let continuityCandidates = strongSameRoadCandidates + successorCandidates.filter { successor in
                    !strongSameRoadCandidates.contains(where: { $0.segment.elementID == successor.segment.elementID })
                }
                sameRoadExplicit = continuityCandidates.first(where: { $0.speedMph == currentSpeedLimitMph })
                let changedExplicit = continuityCandidates.first(where: {
                    guard let mph = $0.speedMph else { return false }
                    return mph != currentSpeedLimitMph
                })
                // Do not use an untagged sibling/successor to mask a real posted-speed
                // change on the same named road. A changed explicit segment still
                // falls through to the normal confirmation path below.
                if changedExplicit == nil {
                    sameRoadUntagged = continuityCandidates.first(where: { $0.speedMph == nil })
                }
            }

            if hardRoadTakeover != nil {
                // `confirmedOSM` was assigned by current-sample completed-turn geometry.
                // Do not let the previous road's display-continuity machinery override it.
            } else if let continuity = sameRoadExplicit {
                let previousID = improvedCurrentRoadID
                improvedCurrentRoadID = continuity.segment.elementID
                improvedCurrentRoadIdentity = Self.normalizedRoadIdentity(
                    name: continuity.segment.name,
                    reference: continuity.segment.reference
                )
                improvedPendingRoad = nil
                confirmedOSM = continuity
                if previousID != continuity.segment.elementID {
                    let handoffKind = sameRoadSuccessorIDs.contains(continuity.segment.elementID)
                        ? "same-road successor fast handoff"
                        : "same-road fast handoff"
                    logger.log(
                        "IMPROVED TRACE DECISION",
                        "\(handoffKind) \(previousID.map(String.init) ?? "none") → \(continuity.segment.elementID) identity=\(improvedCurrentRoadIdentity ?? "-") limit=\(currentSpeedLimitMph)"
                    )
                }
            } else if let continuity = sameRoadUntagged {
                let previousID = improvedCurrentRoadID
                improvedCurrentRoadID = continuity.segment.elementID
                improvedCurrentRoadIdentity = Self.normalizedRoadIdentity(
                    name: continuity.segment.name,
                    reference: continuity.segment.reference
                )
                improvedPendingRoad = nil
                confirmedOSM = continuity
                improvedDisplayContinuityFresh = true
                improvedDisplayContinuityReason = sameRoadSuccessorIDs.contains(continuity.segment.elementID)
                    ? "OSM same-road successor untagged continuity"
                    : "OSM same-road untagged continuity"
                let continuityKind = sameRoadSuccessorIDs.contains(continuity.segment.elementID)
                    ? "same-road successor untagged continuity"
                    : "same-road untagged continuity"
                logger.log(
                    "IMPROVED TRACE DECISION",
                    "\(continuityKind) \(previousID.map(String.init) ?? "none") → \(continuity.segment.elementID) identity=\(improvedCurrentRoadIdentity ?? "-"); preserve displayed \(currentSpeedLimitMph) mph without refreshing warning freshness"
                )
            } else if best.segment.elementID == improvedCurrentRoadID {
                improvedPendingRoad = nil
                confirmedOSM = best
                if let identity = Self.normalizedRoadIdentity(name: best.segment.name, reference: best.segment.reference) {
                    improvedCurrentRoadIdentity = identity
                }
            } else if margin >= 0.45 || improvedCurrentRoadID == nil {
                if let pending = improvedPendingRoad, pending.id == best.segment.elementID {
                    let next = pending.count + 1
                    improvedPendingRoad = (best.segment.elementID, next)
                    if next >= 2 {
                        let previousIdentity = improvedCurrentRoadIdentity
                        let nextIdentity = Self.normalizedRoadIdentity(
                            name: best.segment.name,
                            reference: best.segment.reference
                        )
                        improvedCurrentRoadID = best.segment.elementID
                        improvedCurrentRoadIdentity = nextIdentity
                        if previousIdentity != nil, nextIdentity != previousIdentity {
                            improvedRoadLimitCacheIdentity = nil
                            improvedRoadLimitCacheMph = 0
                            improvedRoadLimitCacheSupportedAt = nil
                            improvedRoadLimitCacheLocation = nil
                            improvedRoadLimitCacheCourse = -1
                            improvedSameRoadContinuityArmed = false
                            improvedPendingLimit = nil
                            currentLimitWarningEligible = false
                            speedLimitAvailableForWarning = false
                        }
                        improvedPendingRoad = nil
                        confirmedOSM = best
                    } else if best.speedMph == currentSpeedLimitMph, currentSpeedLimitMph > 0 {
                        improvedDisplayContinuityFresh = true
                        improvedDisplayContinuityReason = "OSM pending same-limit road confirmation"
                        logger.log(
                            "IMPROVED TRACE DECISION",
                            "pending same-limit road confirmation way=\(best.segment.elementID) limit=\(currentSpeedLimitMph) confirmation=\(next)/2; suppress stale display clear without refreshing warning freshness"
                        )
                    }
                } else {
                    improvedPendingRoad = (best.segment.elementID, 1)
                    if best.speedMph == currentSpeedLimitMph, currentSpeedLimitMph > 0 {
                        improvedDisplayContinuityFresh = true
                        improvedDisplayContinuityReason = "OSM pending same-limit road confirmation"
                        logger.log(
                            "IMPROVED TRACE DECISION",
                            "pending same-limit road confirmation way=\(best.segment.elementID) limit=\(currentSpeedLimitMph) confirmation=1/2; suppress stale display clear without refreshing warning freshness"
                        )
                    }
                }
            }
        } else {
            improvedLastConfidenceMargin = 0
            logger.log("IMPROVED TRACE OSM MATCH", "no drivable OSM road candidate")
        }

        struct GISScored {
            let segment: PhiladelphiaSpeedSegment
            let match: TraceGeometryMatch
        }
        var gisScored: [GISScored] = []
        for segment in philadelphiaSpeedSegments {
            // Prefer explicit posted-speed segments when geometry is otherwise tied;
            // residential layer still provides a valuable 25-mph neighborhood fill.
            let layerPenalty = segment.residentialLayer ? 0.10 : 0.0
            if let match = traceGeometryMatch(
                parts: segment.parts,
                trace: trace,
                location: location,
                continuityBonus: layerPenalty
            ) {
                gisScored.append(GISScored(segment: segment, match: match))
            }
        }
        gisScored.sort { $0.match.score < $1.match.score }

        let gisBest = gisScored.first
        // v90.26 turn acquisition path: recent trace points still belong to the old
        // road immediately after a turn, so the rolling score can lag for blocks.
        // A City centerline that is extremely close and aligned with the *current*
        // GPS course may be used as the local candidate even before trace history
        // fully rotates onto the new street.
        let gisCurrentGeometryBest = gisScored
            .filter { item in
                item.match.currentDistance <= 12 &&
                item.match.currentAngle <= 20 &&
                item.match.matchedPoints >= max(4, trace.count / 2)
            }
            .min { lhs, rhs in
                lhs.match.currentDistance + lhs.match.currentAngle * 0.20 <
                    rhs.match.currentDistance + rhs.match.currentAngle * 0.20
            }
        if let gisBest {
            logger.log(
                "PHILLY GIS MATCH",
                String(
                    format: "id=%d name=%@ limit=%d layer=%@ score=%.2f dist=%.1fm angle=%.1f matched=%d/%d seg=%.6f,%.6f>%.6f,%.6f",
                    gisBest.segment.objectID,
                    gisBest.segment.name ?? "-",
                    gisBest.segment.speedMph,
                    "street-centerline",
                    gisBest.match.score,
                    gisBest.match.currentDistance,
                    gisBest.match.currentAngle,
                    gisBest.match.matchedPoints,
                    trace.count,
                    gisBest.match.nearestStart.latitude,
                    gisBest.match.nearestStart.longitude,
                    gisBest.match.nearestEnd.latitude,
                    gisBest.match.nearestEnd.longitude
                )
            )
        } else if Self.isInsidePhiladelphiaCoverage(location.coordinate) {
            logger.log("PHILLY GIS MATCH", "no nearby Philadelphia Street Centerline speed segment matched current trace")
        }

        // Protect a confidently matched, explicitly tagged limited-access motorway.
        // This prevents a nearby surface-street City centerline from overriding a
        // true Roosevelt Expressway trip. The field-test false-50 case was tagged
        // OSM `trunk`, not `motorway`, so the Philadelphia 40-mph correction remains
        // able to win there.
        if let confirmedOSM,
           let mph = confirmedOSM.speedMph,
           ["motorway", "motorway_link"].contains(confirmedOSM.segment.highway),
           confirmedOSM.match.currentDistance <= 20,
           confirmedOSM.match.currentAngle <= 45,
           confirmedOSM.match.score <= 2.0 {
            return acceptImprovedLimit(
                mph,
                key: "osm:\(confirmedOSM.segment.elementID)",
                source: "OSM explicit motorway"
            )
        }

        // A close City segment is authoritative in Philadelphia. The 28 m cap is
        // deliberate: it corrects surface-street/expressway parallel geometry while
        // avoiding a distant Boulevard centerline stealing a true expressway trip.
        if let gisCandidate = {
            if let local = gisCurrentGeometryBest,
               location.speed >= 1.5 {
                return local
            }
            if let best = gisBest,
               best.match.currentDistance <= 28,
               best.match.currentAngle <= 60,
               best.match.score <= 2.2 {
                return best
            }
            return nil
        }() {
            let fastTurn = gisCurrentGeometryBest?.segment.objectID == gisCandidate.segment.objectID &&
                !(gisBest?.segment.objectID == gisCandidate.segment.objectID && (gisBest?.match.score ?? 99) <= 2.2)
            if fastTurn {
                logger.log(
                    "PHILLY GIS MATCH",
                    String(
                        format: "current-geometry fast acquisition id=%d name=%@ limit=%d dist=%.1fm angle=%.1f matched=%d/%d",
                        gisCandidate.segment.objectID,
                        gisCandidate.segment.name ?? "-",
                        gisCandidate.segment.speedMph,
                        gisCandidate.match.currentDistance,
                        gisCandidate.match.currentAngle,
                        gisCandidate.match.matchedPoints,
                        trace.count
                    )
                )
            }
            return acceptImprovedLimit(
                gisCandidate.segment.speedMph,
                key: "philly-centerline:\(gisCandidate.segment.objectID)",
                source: fastTurn ? "Philadelphia Street Centerline fast acquisition" : "Philadelphia Street Centerline GIS",
                warningEligible: true
            )
        }

        if let confirmedOSM, let mph = confirmedOSM.speedMph {
            return acceptImprovedLimit(
                mph,
                key: "osm:\(confirmedOSM.segment.elementID)",
                source: "OSM explicit"
            )
        }

        if let confirmedOSM,
           confirmedOSM.speedMph == nil,
           confirmedOSM.match.currentDistance <= 15,
           confirmedOSM.match.currentAngle <= 25,
           confirmedOSM.match.matchedPoints >= max(4, trace.count - 2),
           let identity = improvedCurrentRoadIdentity,
           let consensus = sameRoadOSMSpeedConsensus(identity: identity, at: location) {
            logger.log(
                "IMPROVED TRACE DECISION",
                String(
                    format: "same-road corridor consensus identity=%@ limit=%d explicitWays=%d nearest=%.1fm warningFresh=0",
                    identity,
                    consensus.mph,
                    consensus.count,
                    consensus.nearestMeters
                )
            )
            return acceptImprovedLimit(
                consensus.mph,
                key: "osm-road-consensus:\(identity):\(consensus.mph)",
                source: "OSM same-road corridor consensus",
                warningEligible: false
            )
        }

        if improvedDisplayContinuityFresh, currentSpeedLimitMph > 0 {
            improvedResolutionSource = improvedDisplayContinuityReason
            if improvedRoadLimitCacheIdentity == improvedCurrentRoadIdentity, improvedRoadLimitCacheMph == currentSpeedLimitMph {
                improvedRoadLimitCacheSupportedAt = Date()
                improvedRoadLimitCacheLocation = location
                improvedRoadLimitCacheCourse = location.course
            }
            logger.log(
                "IMPROVED TRACE DECISION",
                "display continuity active source=\(improvedDisplayContinuityReason); preserve displayed \(currentSpeedLimitMph) mph, warning freshness unchanged"
            )
            return currentSpeedLimitMph
        }

        // v90.27: preserve a previously established limit through bounded provider/cache
        // holes when the semantic road is unchanged. With a live untagged OSM match,
        // same-road identity + geometry is sufficient. With no OSM candidate at all,
        // require recent support, bounded travel distance, and compatible course.
        if let cacheIdentity = improvedRoadLimitCacheIdentity,
           cacheIdentity == improvedCurrentRoadIdentity,
           improvedRoadLimitCacheMph > 0,
           let supportedAt = improvedRoadLimitCacheSupportedAt,
           let supportedLocation = improvedRoadLimitCacheLocation,
           Date().timeIntervalSince(supportedAt) <= improvedRoadLimitCacheMaxAgeSeconds {
            var cacheSafe = false
            var cacheReason = ""
            if let confirmedOSM,
               Self.normalizedRoadIdentity(name: confirmedOSM.segment.name, reference: confirmedOSM.segment.reference) == cacheIdentity,
               confirmedOSM.match.currentDistance <= 70,
               confirmedOSM.match.currentAngle <= 35,
               confirmedOSM.match.matchedPoints >= max(4, trace.count - 2) {
                cacheSafe = true
                cacheReason = "live same-road untagged geometry"
                improvedRoadLimitCacheSupportedAt = Date()
                improvedRoadLimitCacheLocation = location
                improvedRoadLimitCacheCourse = location.course
            } else if confirmedOSM == nil {
                let distance = supportedLocation.distance(from: location)
                let courseCompatible: Bool
                if improvedRoadLimitCacheCourse >= 0, location.course >= 0 {
                    courseCompatible = Self.angularDifference(improvedRoadLimitCacheCourse, location.course) <= improvedRoadLimitCacheMaxCourseDeltaDegrees
                } else {
                    courseCompatible = true
                }
                cacheSafe = distance <= improvedRoadLimitCacheMaxDistanceMeters && courseCompatible
                cacheReason = String(format: "provider hole distance=%.0fm courseOK=%d", distance, courseCompatible ? 1 : 0)
            }

            if cacheSafe {
                improvedDisplayContinuityFresh = true
                improvedDisplayContinuityReason = "OSM cached same-road hold"
                improvedLastResolutionWarningEligible = false
                improvedResolutionSource = improvedDisplayContinuityReason
                if currentLimitWarningEligible {
                    currentLimitWarningEligible = false
                    speedLimitAvailableForWarning = false
                    if showSpeedLimit, bluetooth.state == .connected {
                        bluetooth.enqueue(
                            HudCommands.speedWarningThreshold(0),
                            label: "Cached same-road display hold — disable native warning threshold"
                        )
                    }
                }
                logger.log(
                    "IMPROVED TRACE DECISION",
                    "cached same-road limit hold identity=\(cacheIdentity) limit=\(improvedRoadLimitCacheMph) reason=\(cacheReason) age=\(String(format: "%.1f", Date().timeIntervalSince(supportedAt)))s warningFresh=0"
                )
                return improvedRoadLimitCacheMph
            }
        }

        improvedResolutionSource = confirmedOSM == nil ? "waiting for road confirmation" : "matched road has no explicit speed"
        logger.log(
            "IMPROVED TRACE DECISION",
            "no fresh speed source; \(improvedResolutionSource); stale display will clear after \(Int(improvedDisplayGraceSeconds))s"
        )
        return currentSpeedLimitMph > 0 ? currentSpeedLimitMph : nil
    }

    private func acceptImprovedLimit(
        _ mph: Int,
        key: String,
        source: String,
        warningEligible: Bool = true
    ) -> Int? {
        guard mph > 0 else { return nil }
        if currentSpeedLimitMph == mph,
           improvedResolutionSource == source {
            improvedPendingLimit = nil
            improvedLastResolutionFresh = true
            improvedLastResolutionWarningEligible = warningEligible
            improvedResolutionSource = source
            improvedSameRoadContinuityArmed = true
            logger.log("IMPROVED TRACE DECISION", "retain \(mph) mph source=\(source)")
            return mph
        }

        if let pending = improvedPendingLimit,
           pending.key == key,
           pending.mph == mph,
           pending.source == source {
            let next = pending.count + 1
            improvedPendingLimit = (key, mph, next, source)
            logger.log("IMPROVED TRACE DECISION", "confirm \(mph) mph source=\(source) confirmation=\(next)/2")
            if next >= 2 {
                improvedPendingLimit = nil
                improvedLastResolutionFresh = true
                improvedLastResolutionWarningEligible = warningEligible
                improvedResolutionSource = source
                improvedSameRoadContinuityArmed = true
                logger.log("SPEED LIMIT", "Improved Trace accepted \(mph) mph source=\(source)")
                return mph
            }
        } else {
            improvedPendingLimit = (key, mph, 1, source)
            logger.log("IMPROVED TRACE DECISION", "new pending \(mph) mph source=\(source) confirmation=1/2")
        }

        // v90.28 field fix: a same-road successor can already be a strong,
        // explicit candidate with exactly the currently displayed speed while the
        // speed-source confirmation state is only 1/2. v90.27 allowed the four-
        // second stale timer to blank the sign during that single confirmation
        // sample (observed twice on MLK). Preserve *display* continuity only.
        // Warning freshness remains unchanged until the normal 2/2 acceptance.
        if currentSpeedLimitMph == mph {
            improvedDisplayContinuityFresh = true
            improvedDisplayContinuityReason = "pending same-limit source confirmation"
            improvedLastResolutionWarningEligible = false
            improvedResolutionSource = improvedDisplayContinuityReason
            if currentLimitWarningEligible {
                currentLimitWarningEligible = false
                speedLimitAvailableForWarning = false
                if showSpeedLimit, bluetooth.state == .connected {
                    bluetooth.enqueue(
                        HudCommands.speedWarningThreshold(0),
                        label: "Pending same-limit confirmation — disable native warning threshold"
                    )
                }
            }
            logger.log(
                "IMPROVED TRACE DECISION",
                "pending same displayed limit \(mph) mph source=\(source); suppress stale display clear while confirmation completes warningFresh=0"
            )
            return mph
        }

        improvedResolutionSource = "pending \(source)"
        return currentSpeedLimitMph > 0 ? currentSpeedLimitMph : nil
    }

    private static func resolvedKmh(
        for segment: ImprovedOSMSegment,
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
