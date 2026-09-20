import Foundation
import Observation

enum HudMapAppearance: String, CaseIterable, Identifiable {
    case followSource
    case darkHUD
    case lightHUD

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followSource: return "Follow source"
        case .darkHUD: return "Dark HUD"
        case .lightHUD: return "Light HUD"
        }
    }
}

enum HudManeuverWarningTarget: String, CaseIterable, Identifiable {
    case maneuverArrow
    case distance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maneuverArrow: return "Turn arrow"
        case .distance: return "Distance"
        }
    }

    var systemImage: String {
        switch self {
        case .maneuverArrow: return "arrow.turn.up.right"
        case .distance: return "ruler"
        }
    }
}

enum HudMapDesignerComponent: String, CaseIterable, Identifiable {
    case speed
    case speedLimit
    case map
    case turningStreet
    case maneuver
    case distance
    case lanes
    case eta
    case timeLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: return "Speed"
        case .speedLimit: return "Speed limit"
        case .map: return "Map"
        case .turningStreet: return "Street"
        case .maneuver: return "Maneuver"
        case .distance: return "Distance"
        case .lanes: return "Lanes"
        case .eta: return "ETA"
        case .timeLeft: return "Time left"
        }
    }

    var systemImage: String {
        switch self {
        case .speed: return "speedometer"
        case .speedLimit: return "signpost.right"
        case .map: return "map"
        case .turningStreet: return "textformat"
        case .maneuver: return "arrow.turn.up.right"
        case .distance: return "ruler"
        case .lanes: return "arrow.triangle.branch"
        case .eta: return "clock"
        case .timeLeft: return "timer"
        }
    }
}

/// Complete persisted Map Mode presentation state used by the three design presets.
///
/// v90.35.3.13.3 deliberately snapshots the legacy calibration values too. That
/// lets Preset 1 reproduce the exact layout a user tuned before the designer was
/// introduced instead of replacing it with a new default layout.
private struct HudMapModePresetSnapshot: Codable {
    var leftScale: Double
    var centerScale: Double
    var rightScale: Double
    var leftOffsetX: Double
    var leftOffsetY: Double
    var centerOffsetX: Double
    var centerOffsetY: Double
    var rightOffsetX: Double
    var rightOffsetY: Double

    var maneuverArrowScale: Double
    var maneuverArrowThickness: Double
    var maneuverOffsetX: Double
    var maneuverOffsetY: Double
    var turningStreetScale: Double
    var distanceScale: Double
    var laneScale: Double
    var laneArrowThickness: Double
    // Optional for backwards-compatible decoding of presets saved before v90.35.3.22.
    var laneArrowHeadScale: Double?
    var laneArrowBodyLength: Double?
    var laneSpacing: Double
    var laneActiveEmphasis: Double
    var laneInactiveGray: Double
    var laneOffsetX: Double
    var laneOffsetY: Double
    var etaScale: Double
    var etaOffsetX: Double
    var etaOffsetY: Double
    var streetToManeuverSpacing: Double
    var maneuverToLaneSpacing: Double
    var laneToETASpacing: Double

    var sourceMapZoom: Double
    var sourceMapOffsetX: Double
    var sourceMapOffsetY: Double
    var mapFadeHorizontal: Double
    var mapFadeVertical: Double
    var speedLimitSignHeightScale: Double
    var speedLimitFontScale: Double

    var showSpeed: Bool
    var showSpeedLimit: Bool
    var showMap: Bool
    var showTurningStreet: Bool
    var showManeuver: Bool
    var showDistance: Bool
    var showLaneGuidance: Bool
    var showETA: Bool
    var showTimeLeft: Bool
    var nativeOBDSpeedOverlayExperiment: Bool
    var mapAppearanceRaw: String

    // Designer-only deltas are layered over the legacy calibration above. This
    // makes the migration lossless: every new delta starts at zero in Preset 1.
    var speedScale: Double
    var timeLeftScale: Double
    var designerSpeedOffsetX: Double
    var designerSpeedOffsetY: Double
    var designerSpeedLimitOffsetX: Double
    var designerSpeedLimitOffsetY: Double
    var designerMapOffsetX: Double
    var designerMapOffsetY: Double
    var designerStreetOffsetX: Double
    var designerStreetOffsetY: Double
    var designerManeuverOffsetX: Double
    var designerManeuverOffsetY: Double
    var designerDistanceOffsetX: Double
    var designerDistanceOffsetY: Double
    var designerLaneOffsetX: Double
    var designerLaneOffsetY: Double
    var designerETAOffsetX: Double
    var designerETAOffsetY: Double
    var designerTimeLeftOffsetX: Double
    var designerTimeLeftOffsetY: Double

    @MainActor
    init(settings: HudMapModeSettings) {
        leftScale = settings.leftScale
        centerScale = settings.centerScale
        rightScale = settings.rightScale
        leftOffsetX = settings.leftOffsetX
        leftOffsetY = settings.leftOffsetY
        centerOffsetX = settings.centerOffsetX
        centerOffsetY = settings.centerOffsetY
        rightOffsetX = settings.rightOffsetX
        rightOffsetY = settings.rightOffsetY
        maneuverArrowScale = settings.maneuverArrowScale
        maneuverArrowThickness = settings.maneuverArrowThickness
        maneuverOffsetX = settings.maneuverOffsetX
        maneuverOffsetY = settings.maneuverOffsetY
        turningStreetScale = settings.turningStreetScale
        distanceScale = settings.distanceScale
        laneScale = settings.laneScale
        laneArrowThickness = settings.laneArrowThickness
        laneArrowHeadScale = settings.laneArrowHeadScale
        laneArrowBodyLength = settings.laneArrowBodyLength
        laneSpacing = settings.laneSpacing
        laneActiveEmphasis = settings.laneActiveEmphasis
        laneInactiveGray = settings.laneInactiveGray
        laneOffsetX = settings.laneOffsetX
        laneOffsetY = settings.laneOffsetY
        etaScale = settings.etaScale
        etaOffsetX = settings.etaOffsetX
        etaOffsetY = settings.etaOffsetY
        streetToManeuverSpacing = settings.streetToManeuverSpacing
        maneuverToLaneSpacing = settings.maneuverToLaneSpacing
        laneToETASpacing = settings.laneToETASpacing
        sourceMapZoom = settings.sourceMapZoom
        sourceMapOffsetX = settings.sourceMapOffsetX
        sourceMapOffsetY = settings.sourceMapOffsetY
        mapFadeHorizontal = settings.mapFadeHorizontal
        mapFadeVertical = settings.mapFadeVertical
        speedLimitSignHeightScale = settings.speedLimitSignHeightScale
        speedLimitFontScale = settings.speedLimitFontScale
        showSpeed = settings.showSpeed
        showSpeedLimit = settings.showSpeedLimit
        showMap = settings.showMap
        showTurningStreet = settings.showTurningStreet
        showManeuver = settings.showManeuver
        showDistance = settings.showDistance
        showLaneGuidance = settings.showLaneGuidance
        showETA = settings.showETA
        showTimeLeft = settings.showTimeLeft
        nativeOBDSpeedOverlayExperiment = settings.nativeOBDSpeedOverlayExperiment
        mapAppearanceRaw = settings.mapAppearance.rawValue
        speedScale = settings.speedScale
        timeLeftScale = settings.timeLeftScale
        designerSpeedOffsetX = settings.designerSpeedOffsetX
        designerSpeedOffsetY = settings.designerSpeedOffsetY
        designerSpeedLimitOffsetX = settings.designerSpeedLimitOffsetX
        designerSpeedLimitOffsetY = settings.designerSpeedLimitOffsetY
        designerMapOffsetX = settings.designerMapOffsetX
        designerMapOffsetY = settings.designerMapOffsetY
        designerStreetOffsetX = settings.designerStreetOffsetX
        designerStreetOffsetY = settings.designerStreetOffsetY
        designerManeuverOffsetX = settings.designerManeuverOffsetX
        designerManeuverOffsetY = settings.designerManeuverOffsetY
        designerDistanceOffsetX = settings.designerDistanceOffsetX
        designerDistanceOffsetY = settings.designerDistanceOffsetY
        designerLaneOffsetX = settings.designerLaneOffsetX
        designerLaneOffsetY = settings.designerLaneOffsetY
        designerETAOffsetX = settings.designerETAOffsetX
        designerETAOffsetY = settings.designerETAOffsetY
        designerTimeLeftOffsetX = settings.designerTimeLeftOffsetX
        designerTimeLeftOffsetY = settings.designerTimeLeftOffsetY
    }
}

/// Persisted presentation controls for the custom Map Mode renderer.
///
/// These values affect only the custom map-mode composition. They do not alter
/// the stock Freeride/Navigation dashboard widget configuration.
@MainActor
@Observable
final class HudMapModeSettings {
    private let defaults = UserDefaults.standard
    private var presetSystemReady = false
    private var isApplyingPreset = false

    private static let activePresetKey = "HUD.MapMode.Designer.activePreset"
    private static let presetMigrationKey = "HUD.MapMode.Designer.v1Migrated"
    private static let importedBaselineKey = "HUD.MapMode.Designer.importedBaseline"

    var activePresetIndex: Int {
        didSet { defaults.set(activePresetIndex, forKey: Self.activePresetKey) }
    }

    var leftScale: Double { didSet { persist(leftScale, key: "HUD.MapMode.leftScale") } }
    var centerScale: Double { didSet { persist(centerScale, key: "HUD.MapMode.centerScale") } }
    var rightScale: Double { didSet { persist(rightScale, key: "HUD.MapMode.rightScale") } }

    // Physical 480×240 canvas calibration. Offsets are stored in final-render pixels.
    var leftOffsetX: Double { didSet { persist(leftOffsetX, key: "HUD.MapMode.leftOffsetX") } }
    var leftOffsetY: Double { didSet { persist(leftOffsetY, key: "HUD.MapMode.leftOffsetY") } }
    var centerOffsetX: Double { didSet { persist(centerOffsetX, key: "HUD.MapMode.centerOffsetX") } }
    var centerOffsetY: Double { didSet { persist(centerOffsetY, key: "HUD.MapMode.centerOffsetY") } }
    var rightOffsetX: Double { didSet { persist(rightOffsetX, key: "HUD.MapMode.rightOffsetX") } }
    var rightOffsetY: Double { didSet { persist(rightOffsetY, key: "HUD.MapMode.rightOffsetY") } }

    // Right-side turn/lane/ETA fine tuning. These affect only the rendered JPEG;
    // they do not alter Route Guidance parsing or the U2W transport.
    var maneuverArrowScale: Double { didSet { persist(maneuverArrowScale, key: "HUD.MapMode.maneuverArrowScale") } }
    var maneuverArrowThickness: Double { didSet { persist(maneuverArrowThickness, key: "HUD.MapMode.maneuverArrowThickness") } }
    var maneuverOffsetX: Double { didSet { persist(maneuverOffsetX, key: "HUD.MapMode.maneuverOffsetX") } }
    var maneuverOffsetY: Double { didSet { persist(maneuverOffsetY, key: "HUD.MapMode.maneuverOffsetY") } }
    var turningStreetScale: Double { didSet { persist(turningStreetScale, key: "HUD.MapMode.turningStreetScale") } }
    var distanceScale: Double { didSet { persist(distanceScale, key: "HUD.MapMode.distanceScale") } }

    var laneScale: Double { didSet { persist(laneScale, key: "HUD.MapMode.laneScale") } }
    var laneArrowThickness: Double { didSet { persist(laneArrowThickness, key: "HUD.MapMode.laneArrowThickness") } }
    /// Independent filled-arrowhead size. Keeps the thin shaft legible while making
    /// the head survive the 480×240 HUD + JPEG presentation path.
    var laneArrowHeadScale: Double { didSet { persist(laneArrowHeadScale, key: "HUD.MapMode.laneArrowHeadScale") } }
    /// Independent vertical shaft/body length. 1.0 preserves the v90.35.3.20 geometry;
    /// smaller values shorten the stem without shrinking the head.
    var laneArrowBodyLength: Double { didSet { persist(laneArrowBodyLength, key: "HUD.MapMode.laneArrowBodyLength") } }
    var laneSpacing: Double { didSet { persist(laneSpacing, key: "HUD.MapMode.laneSpacing") } }
    var laneActiveEmphasis: Double { didSet { persist(laneActiveEmphasis, key: "HUD.MapMode.laneActiveEmphasis") } }
    var laneInactiveGray: Double { didSet { persist(laneInactiveGray, key: "HUD.MapMode.laneInactiveGray") } }
    var laneOffsetX: Double { didSet { persist(laneOffsetX, key: "HUD.MapMode.laneOffsetX") } }
    var laneOffsetY: Double { didSet { persist(laneOffsetY, key: "HUD.MapMode.laneOffsetY") } }

    var etaScale: Double { didSet { persist(etaScale, key: "HUD.MapMode.etaScale") } }
    var etaOffsetX: Double { didSet { persist(etaOffsetX, key: "HUD.MapMode.etaOffsetX") } }
    var etaOffsetY: Double { didSet { persist(etaOffsetY, key: "HUD.MapMode.etaOffsetY") } }

    // Independent vertical gaps between the four right-side content blocks.
    var streetToManeuverSpacing: Double { didSet { persist(streetToManeuverSpacing, key: "HUD.MapMode.streetToManeuverSpacing") } }
    var maneuverToLaneSpacing: Double { didSet { persist(maneuverToLaneSpacing, key: "HUD.MapMode.maneuverToLaneSpacing") } }
    var laneToETASpacing: Double { didSet { persist(laneToETASpacing, key: "HUD.MapMode.laneToETASpacing") } }

    // Real U2W 800×480 MainVideo crop calibration.
    var sourceMapZoom: Double { didSet { persist(sourceMapZoom, key: "HUD.MapMode.sourceMapZoom") } }
    var sourceMapOffsetX: Double { didSet { persist(sourceMapOffsetX, key: "HUD.MapMode.sourceMapOffsetX") } }
    var sourceMapOffsetY: Double { didSet { persist(sourceMapOffsetY, key: "HUD.MapMode.sourceMapOffsetY") } }
    var mapFadeHorizontal: Double { didSet { persist(mapFadeHorizontal, key: "HUD.MapMode.mapFadeHorizontal") } }
    var mapFadeVertical: Double { didSet { persist(mapFadeVertical, key: "HUD.MapMode.mapFadeVertical") } }

    // Left-side speed-limit sign fine tuning.
    var speedLimitSignHeightScale: Double { didSet { persist(speedLimitSignHeightScale, key: "HUD.MapMode.speedLimitSignHeightScale") } }
    var speedLimitFontScale: Double { didSet { persist(speedLimitFontScale, key: "HUD.MapMode.speedLimitFontScale") } }

    var showSpeed: Bool { didSet { persist(showSpeed, key: "HUD.MapMode.showSpeed") } }
    var showSpeedLimit: Bool { didSet { persist(showSpeedLimit, key: "HUD.MapMode.showSpeedLimit") } }
    var showMap: Bool { didSet { persist(showMap, key: "HUD.MapMode.showMap") } }
    var showTurningStreet: Bool { didSet { persist(showTurningStreet, key: "HUD.MapMode.showTurningStreet") } }
    var showManeuver: Bool { didSet { persist(showManeuver, key: "HUD.MapMode.showManeuver") } }
    var showDistance: Bool { didSet { persist(showDistance, key: "HUD.MapMode.showDistance") } }
    var showLaneGuidance: Bool { didSet { persist(showLaneGuidance, key: "HUD.MapMode.showLaneGuidance") } }
    var showETA: Bool { didSet { persist(showETA, key: "HUD.MapMode.showETA") } }
    var showTimeLeft: Bool { didSet { persist(showTimeLeft, key: "HUD.MapMode.showTimeLeft") } }

    var nativeOBDSpeedOverlayExperiment: Bool {
        didSet { persist(nativeOBDSpeedOverlayExperiment, key: "HUD.MapMode.nativeOBDSpeedOverlayExperiment") }
    }

    var mapAppearance: HudMapAppearance {
        didSet {
            defaults.set(mapAppearance.rawValue, forKey: "HUD.MapMode.mapAppearance")
            presetValueDidChange()
        }
    }

    // v90.35.3.24.4 close-maneuver warning. These are intentionally global,
    // not design-preset values: changing visual presets should not silently
    // change when or how an approaching-turn warning is delivered.
    var maneuverWarningEnabled: Bool {
        didSet { defaults.set(maneuverWarningEnabled, forKey: "HUD.MapMode.maneuverWarning.enabled") }
    }
    var maneuverWarningTarget: HudManeuverWarningTarget {
        didSet { defaults.set(maneuverWarningTarget.rawValue, forKey: "HUD.MapMode.maneuverWarning.target") }
    }
    var maneuverWarningThresholdFeet: Int {
        didSet { defaults.set(maneuverWarningThresholdFeet, forKey: "HUD.MapMode.maneuverWarning.thresholdFeet") }
    }
    var maneuverWarningBlinkCount: Int {
        didSet { defaults.set(maneuverWarningBlinkCount, forKey: "HUD.MapMode.maneuverWarning.blinkCount") }
    }
    var maneuverWarningIntervalSeconds: Double {
        didSet { defaults.set(maneuverWarningIntervalSeconds, forKey: "HUD.MapMode.maneuverWarning.intervalSeconds") }
    }

    // v90.35.3.13.3 designer values. They are intentionally *deltas* layered
    // on top of the user's existing calibration, so migration cannot move any
    // previously tuned component. All offsets are final 480×240 canvas pixels.
    var speedScale: Double { didSet { persist(speedScale, key: "HUD.MapMode.Designer.speedScale") } }
    var timeLeftScale: Double { didSet { persist(timeLeftScale, key: "HUD.MapMode.Designer.timeLeftScale") } }
    var designerSpeedOffsetX: Double { didSet { persist(designerSpeedOffsetX, key: "HUD.MapMode.Designer.speed.x") } }
    var designerSpeedOffsetY: Double { didSet { persist(designerSpeedOffsetY, key: "HUD.MapMode.Designer.speed.y") } }
    var designerSpeedLimitOffsetX: Double { didSet { persist(designerSpeedLimitOffsetX, key: "HUD.MapMode.Designer.speedLimit.x") } }
    var designerSpeedLimitOffsetY: Double { didSet { persist(designerSpeedLimitOffsetY, key: "HUD.MapMode.Designer.speedLimit.y") } }
    var designerMapOffsetX: Double { didSet { persist(designerMapOffsetX, key: "HUD.MapMode.Designer.map.x") } }
    var designerMapOffsetY: Double { didSet { persist(designerMapOffsetY, key: "HUD.MapMode.Designer.map.y") } }
    var designerStreetOffsetX: Double { didSet { persist(designerStreetOffsetX, key: "HUD.MapMode.Designer.street.x") } }
    var designerStreetOffsetY: Double { didSet { persist(designerStreetOffsetY, key: "HUD.MapMode.Designer.street.y") } }
    var designerManeuverOffsetX: Double { didSet { persist(designerManeuverOffsetX, key: "HUD.MapMode.Designer.maneuver.x") } }
    var designerManeuverOffsetY: Double { didSet { persist(designerManeuverOffsetY, key: "HUD.MapMode.Designer.maneuver.y") } }
    var designerDistanceOffsetX: Double { didSet { persist(designerDistanceOffsetX, key: "HUD.MapMode.Designer.distance.x") } }
    var designerDistanceOffsetY: Double { didSet { persist(designerDistanceOffsetY, key: "HUD.MapMode.Designer.distance.y") } }
    var designerLaneOffsetX: Double { didSet { persist(designerLaneOffsetX, key: "HUD.MapMode.Designer.lanes.x") } }
    var designerLaneOffsetY: Double { didSet { persist(designerLaneOffsetY, key: "HUD.MapMode.Designer.lanes.y") } }
    var designerETAOffsetX: Double { didSet { persist(designerETAOffsetX, key: "HUD.MapMode.Designer.eta.x") } }
    var designerETAOffsetY: Double { didSet { persist(designerETAOffsetY, key: "HUD.MapMode.Designer.eta.y") } }
    var designerTimeLeftOffsetX: Double { didSet { persist(designerTimeLeftOffsetX, key: "HUD.MapMode.Designer.timeLeft.x") } }
    var designerTimeLeftOffsetY: Double { didSet { persist(designerTimeLeftOffsetY, key: "HUD.MapMode.Designer.timeLeft.y") } }

    init() {
        let store = UserDefaults.standard

        func bool(_ key: String, default fallback: Bool) -> Bool {
            store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
        }

        func double(_ key: String, default fallback: Double) -> Double {
            store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
        }

        func integer(_ key: String, default fallback: Int) -> Int {
            store.object(forKey: key) == nil ? fallback : store.integer(forKey: key)
        }

        leftScale = min(1.45, max(0.60, double("HUD.MapMode.leftScale", default: 1.0)))
        centerScale = min(1.45, max(0.60, double("HUD.MapMode.centerScale", default: 1.0)))
        rightScale = min(1.45, max(0.60, double("HUD.MapMode.rightScale", default: 1.0)))

        leftOffsetX = min(20, max(-20, double("HUD.MapMode.leftOffsetX", default: 0)))
        leftOffsetY = min(12, max(-12, double("HUD.MapMode.leftOffsetY", default: 0)))
        centerOffsetX = min(20, max(-20, double("HUD.MapMode.centerOffsetX", default: 0)))
        centerOffsetY = min(12, max(-12, double("HUD.MapMode.centerOffsetY", default: 0)))
        rightOffsetX = min(20, max(-20, double("HUD.MapMode.rightOffsetX", default: 0)))
        rightOffsetY = min(12, max(-12, double("HUD.MapMode.rightOffsetY", default: 0)))

        maneuverArrowScale = min(1.60, max(0.60, double("HUD.MapMode.maneuverArrowScale", default: 1.0)))
        maneuverArrowThickness = min(2.50, max(1.00, double("HUD.MapMode.maneuverArrowThickness", default: 1.75)))
        maneuverOffsetX = min(12, max(-12, double("HUD.MapMode.maneuverOffsetX", default: 0)))
        maneuverOffsetY = min(10, max(-10, double("HUD.MapMode.maneuverOffsetY", default: 0)))
        turningStreetScale = min(1.60, max(0.60, double("HUD.MapMode.turningStreetScale", default: 1.0)))
        distanceScale = min(1.60, max(0.60, double("HUD.MapMode.distanceScale", default: 1.0)))

        laneScale = min(1.70, max(0.60, double("HUD.MapMode.laneScale", default: 1.0)))
        laneArrowThickness = min(2.50, max(0.60, double("HUD.MapMode.laneArrowThickness", default: 1.75)))
        laneArrowHeadScale = min(1.80, max(0.80, double("HUD.MapMode.laneArrowHeadScale", default: 1.35)))
        laneArrowBodyLength = min(1.00, max(0.55, double("HUD.MapMode.laneArrowBodyLength", default: 0.78)))
        laneSpacing = min(8, max(1, double("HUD.MapMode.laneSpacing", default: 3)))
        laneActiveEmphasis = min(1.35, max(1.00, double("HUD.MapMode.laneActiveEmphasis", default: 1.10)))
        laneInactiveGray = min(0.80, max(0.12, double("HUD.MapMode.laneInactiveGray", default: 0.40)))
        laneOffsetX = min(12, max(-12, double("HUD.MapMode.laneOffsetX", default: 0)))
        laneOffsetY = min(10, max(-10, double("HUD.MapMode.laneOffsetY", default: 0)))

        etaScale = min(1.60, max(0.60, double("HUD.MapMode.etaScale", default: 1.0)))
        etaOffsetX = min(12, max(-12, double("HUD.MapMode.etaOffsetX", default: 0)))
        etaOffsetY = min(10, max(-10, double("HUD.MapMode.etaOffsetY", default: 0)))
        streetToManeuverSpacing = min(20, max(0, double("HUD.MapMode.streetToManeuverSpacing", default: 4)))
        maneuverToLaneSpacing = min(20, max(0, double("HUD.MapMode.maneuverToLaneSpacing", default: 4)))
        laneToETASpacing = min(20, max(0, double("HUD.MapMode.laneToETASpacing", default: 4)))

        sourceMapZoom = min(2.60, max(0.80, double("HUD.MapMode.sourceMapZoom", default: 1.55)))
        sourceMapOffsetX = min(1.0, max(-1.0, double("HUD.MapMode.sourceMapOffsetX", default: 0.22)))
        sourceMapOffsetY = min(1.0, max(-1.0, double("HUD.MapMode.sourceMapOffsetY", default: 0.0)))
        mapFadeHorizontal = min(0.35, max(0.0, double("HUD.MapMode.mapFadeHorizontal", default: 0.045)))
        mapFadeVertical = min(0.35, max(0.0, double("HUD.MapMode.mapFadeVertical", default: 0.0)))
        speedLimitSignHeightScale = min(2.00, max(0.80, double("HUD.MapMode.speedLimitSignHeightScale", default: 1.0)))
        speedLimitFontScale = min(1.60, max(0.70, double("HUD.MapMode.speedLimitFontScale", default: 1.0)))

        showSpeed = bool("HUD.MapMode.showSpeed", default: true)
        showSpeedLimit = bool("HUD.MapMode.showSpeedLimit", default: true)
        showMap = bool("HUD.MapMode.showMap", default: true)
        showTurningStreet = bool("HUD.MapMode.showTurningStreet", default: true)
        showManeuver = bool("HUD.MapMode.showManeuver", default: true)
        showDistance = bool("HUD.MapMode.showDistance", default: true)
        showLaneGuidance = bool("HUD.MapMode.showLaneGuidance", default: true)
        showETA = bool("HUD.MapMode.showETA", default: true)
        showTimeLeft = bool("HUD.MapMode.showTimeLeft", default: true)
        nativeOBDSpeedOverlayExperiment = bool("HUD.MapMode.nativeOBDSpeedOverlayExperiment", default: false)

        let raw = store.string(forKey: "HUD.MapMode.mapAppearance") ?? HudMapAppearance.followSource.rawValue
        mapAppearance = HudMapAppearance(rawValue: raw) ?? .followSource

        maneuverWarningEnabled = bool("HUD.MapMode.maneuverWarning.enabled", default: true)
        let warningTargetRaw = store.string(forKey: "HUD.MapMode.maneuverWarning.target") ?? HudManeuverWarningTarget.distance.rawValue
        maneuverWarningTarget = HudManeuverWarningTarget(rawValue: warningTargetRaw) ?? .distance
        maneuverWarningThresholdFeet = min(2000, max(100, integer("HUD.MapMode.maneuverWarning.thresholdFeet", default: 500)))
        maneuverWarningBlinkCount = min(5, max(2, integer("HUD.MapMode.maneuverWarning.blinkCount", default: 3)))
        maneuverWarningIntervalSeconds = min(2.0, max(0.5, double("HUD.MapMode.maneuverWarning.intervalSeconds", default: 0.75)))

        speedScale = min(1.80, max(0.50, double("HUD.MapMode.Designer.speedScale", default: 1.0)))
        timeLeftScale = min(1.80, max(0.50, double("HUD.MapMode.Designer.timeLeftScale", default: 1.0)))
        designerSpeedOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.speed.x", default: 0), axis: .x)
        designerSpeedOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.speed.y", default: 0), axis: .y)
        designerSpeedLimitOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.speedLimit.x", default: 0), axis: .x)
        designerSpeedLimitOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.speedLimit.y", default: 0), axis: .y)
        designerMapOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.map.x", default: 0), axis: .x)
        designerMapOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.map.y", default: 0), axis: .y)
        designerStreetOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.street.x", default: 0), axis: .x)
        designerStreetOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.street.y", default: 0), axis: .y)
        designerManeuverOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.maneuver.x", default: 0), axis: .x)
        designerManeuverOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.maneuver.y", default: 0), axis: .y)
        designerDistanceOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.distance.x", default: 0), axis: .x)
        designerDistanceOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.distance.y", default: 0), axis: .y)
        designerLaneOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.lanes.x", default: 0), axis: .x)
        designerLaneOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.lanes.y", default: 0), axis: .y)
        designerETAOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.eta.x", default: 0), axis: .x)
        designerETAOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.eta.y", default: 0), axis: .y)
        designerTimeLeftOffsetX = Self.clampDesigner(double("HUD.MapMode.Designer.timeLeft.x", default: 0), axis: .x)
        designerTimeLeftOffsetY = Self.clampDesigner(double("HUD.MapMode.Designer.timeLeft.y", default: 0), axis: .y)

        activePresetIndex = min(2, max(0, store.integer(forKey: Self.activePresetKey)))

        // First launch of the designer: capture the exact legacy/current layout
        // as Preset 1 *before* loading or applying any preset state. Presets 2/3
        // start as copies so experimentation begins from the known-good layout.
        presetSystemReady = true
        if !store.bool(forKey: Self.presetMigrationKey) {
            activePresetIndex = 0
            store.set(0, forKey: Self.activePresetKey)
            let imported = HudMapModePresetSnapshot(settings: self)
            if let data = try? JSONEncoder().encode(imported) {
                store.set(data, forKey: Self.importedBaselineKey)
                for index in 0..<3 {
                    store.set(data, forKey: Self.presetKey(index))
                }
            }
            store.set(true, forKey: Self.presetMigrationKey)
        } else if let preset = loadPreset(activePresetIndex) {
            apply(preset)
        } else {
            saveCurrentPreset()
        }
    }

    private enum DesignerAxis { case x, y }

    private static func clampDesigner(_ value: Double, axis: DesignerAxis) -> Double {
        switch axis {
        case .x: return min(210, max(-210, value))
        case .y: return min(110, max(-110, value))
        }
    }

    private static func presetKey(_ index: Int) -> String {
        "HUD.MapMode.Designer.preset.v1.\(index)"
    }

    private func persist(_ value: Double, key: String) {
        defaults.set(value, forKey: key)
        presetValueDidChange()
    }

    private func persist(_ value: Bool, key: String) {
        defaults.set(value, forKey: key)
        presetValueDidChange()
    }

    private func presetValueDidChange() {
        guard presetSystemReady, !isApplyingPreset else { return }
        saveCurrentPreset()
    }

    private func loadPreset(_ index: Int) -> HudMapModePresetSnapshot? {
        guard let data = defaults.data(forKey: Self.presetKey(index)) else { return nil }
        return try? JSONDecoder().decode(HudMapModePresetSnapshot.self, from: data)
    }

    private func save(_ snapshot: HudMapModePresetSnapshot, to index: Int) {
        guard (0..<3).contains(index), let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.presetKey(index))
    }

    func saveCurrentPreset() {
        guard presetSystemReady, !isApplyingPreset else { return }
        save(HudMapModePresetSnapshot(settings: self), to: activePresetIndex)
    }

    func selectPreset(_ index: Int) {
        guard (0..<3).contains(index), index != activePresetIndex else {
            saveCurrentPreset()
            return
        }
        saveCurrentPreset()
        let previous = HudMapModePresetSnapshot(settings: self)
        activePresetIndex = index
        if let target = loadPreset(index) {
            apply(target)
        } else {
            save(previous, to: index)
        }
    }

    /// Copy the currently visible design into another slot and switch to it.
    func duplicateCurrentPreset(to index: Int) {
        guard (0..<3).contains(index) else { return }
        let snapshot = HudMapModePresetSnapshot(settings: self)
        save(snapshot, to: index)
        activePresetIndex = index
        apply(snapshot)
    }

    /// Restore the pre-designer layout captured during migration. This provides
    /// a non-destructive safety net even after Preset 1 has been edited later.
    func restoreImportedLayout() {
        guard let data = defaults.data(forKey: Self.importedBaselineKey),
              let snapshot = try? JSONDecoder().decode(HudMapModePresetSnapshot.self, from: data)
        else { return }
        apply(snapshot)
        saveCurrentPreset()
    }

    private func apply(_ preset: HudMapModePresetSnapshot) {
        isApplyingPreset = true
        defer {
            isApplyingPreset = false
            saveCurrentPreset()
        }

        leftScale = preset.leftScale
        centerScale = preset.centerScale
        rightScale = preset.rightScale
        leftOffsetX = preset.leftOffsetX
        leftOffsetY = preset.leftOffsetY
        centerOffsetX = preset.centerOffsetX
        centerOffsetY = preset.centerOffsetY
        rightOffsetX = preset.rightOffsetX
        rightOffsetY = preset.rightOffsetY
        maneuverArrowScale = preset.maneuverArrowScale
        maneuverArrowThickness = preset.maneuverArrowThickness
        maneuverOffsetX = preset.maneuverOffsetX
        maneuverOffsetY = preset.maneuverOffsetY
        turningStreetScale = preset.turningStreetScale
        distanceScale = preset.distanceScale
        laneScale = preset.laneScale
        laneArrowThickness = preset.laneArrowThickness
        laneArrowHeadScale = min(1.80, max(0.80, preset.laneArrowHeadScale ?? 1.35))
        laneArrowBodyLength = min(1.00, max(0.55, preset.laneArrowBodyLength ?? 0.78))
        laneSpacing = preset.laneSpacing
        laneActiveEmphasis = preset.laneActiveEmphasis
        laneInactiveGray = preset.laneInactiveGray
        laneOffsetX = preset.laneOffsetX
        laneOffsetY = preset.laneOffsetY
        etaScale = preset.etaScale
        etaOffsetX = preset.etaOffsetX
        etaOffsetY = preset.etaOffsetY
        streetToManeuverSpacing = preset.streetToManeuverSpacing
        maneuverToLaneSpacing = preset.maneuverToLaneSpacing
        laneToETASpacing = preset.laneToETASpacing
        sourceMapZoom = preset.sourceMapZoom
        sourceMapOffsetX = preset.sourceMapOffsetX
        sourceMapOffsetY = preset.sourceMapOffsetY
        mapFadeHorizontal = preset.mapFadeHorizontal
        mapFadeVertical = preset.mapFadeVertical
        speedLimitSignHeightScale = preset.speedLimitSignHeightScale
        speedLimitFontScale = preset.speedLimitFontScale
        showSpeed = preset.showSpeed
        showSpeedLimit = preset.showSpeedLimit
        showMap = preset.showMap
        showTurningStreet = preset.showTurningStreet
        showManeuver = preset.showManeuver
        showDistance = preset.showDistance
        showLaneGuidance = preset.showLaneGuidance
        showETA = preset.showETA
        showTimeLeft = preset.showTimeLeft
        nativeOBDSpeedOverlayExperiment = preset.nativeOBDSpeedOverlayExperiment
        mapAppearance = HudMapAppearance(rawValue: preset.mapAppearanceRaw) ?? .followSource
        speedScale = preset.speedScale
        timeLeftScale = preset.timeLeftScale
        designerSpeedOffsetX = preset.designerSpeedOffsetX
        designerSpeedOffsetY = preset.designerSpeedOffsetY
        designerSpeedLimitOffsetX = preset.designerSpeedLimitOffsetX
        designerSpeedLimitOffsetY = preset.designerSpeedLimitOffsetY
        designerMapOffsetX = preset.designerMapOffsetX
        designerMapOffsetY = preset.designerMapOffsetY
        designerStreetOffsetX = preset.designerStreetOffsetX
        designerStreetOffsetY = preset.designerStreetOffsetY
        designerManeuverOffsetX = preset.designerManeuverOffsetX
        designerManeuverOffsetY = preset.designerManeuverOffsetY
        designerDistanceOffsetX = preset.designerDistanceOffsetX
        designerDistanceOffsetY = preset.designerDistanceOffsetY
        designerLaneOffsetX = preset.designerLaneOffsetX
        designerLaneOffsetY = preset.designerLaneOffsetY
        designerETAOffsetX = preset.designerETAOffsetX
        designerETAOffsetY = preset.designerETAOffsetY
        designerTimeLeftOffsetX = preset.designerTimeLeftOffsetX
        designerTimeLeftOffsetY = preset.designerTimeLeftOffsetY
    }

    func presetTitle(_ index: Int) -> String {
        switch index {
        case 0: return "Preset 1"
        case 1: return "Preset 2"
        default: return "Preset 3"
        }
    }

    func designerOffset(for component: HudMapDesignerComponent) -> (x: Double, y: Double) {
        switch component {
        case .speed: return (designerSpeedOffsetX, designerSpeedOffsetY)
        case .speedLimit: return (designerSpeedLimitOffsetX, designerSpeedLimitOffsetY)
        case .map: return (designerMapOffsetX, designerMapOffsetY)
        case .turningStreet: return (designerStreetOffsetX, designerStreetOffsetY)
        case .maneuver: return (designerManeuverOffsetX, designerManeuverOffsetY)
        case .distance: return (designerDistanceOffsetX, designerDistanceOffsetY)
        case .lanes: return (designerLaneOffsetX, designerLaneOffsetY)
        case .eta: return (designerETAOffsetX, designerETAOffsetY)
        case .timeLeft: return (designerTimeLeftOffsetX, designerTimeLeftOffsetY)
        }
    }

    func setDesignerOffset(_ component: HudMapDesignerComponent, x: Double, y: Double) {
        let safeX = Self.clampDesigner(x, axis: .x)
        let safeY = Self.clampDesigner(y, axis: .y)
        switch component {
        case .speed:
            designerSpeedOffsetX = safeX; designerSpeedOffsetY = safeY
        case .speedLimit:
            designerSpeedLimitOffsetX = safeX; designerSpeedLimitOffsetY = safeY
        case .map:
            designerMapOffsetX = safeX; designerMapOffsetY = safeY
        case .turningStreet:
            designerStreetOffsetX = safeX; designerStreetOffsetY = safeY
        case .maneuver:
            designerManeuverOffsetX = safeX; designerManeuverOffsetY = safeY
        case .distance:
            designerDistanceOffsetX = safeX; designerDistanceOffsetY = safeY
        case .lanes:
            designerLaneOffsetX = safeX; designerLaneOffsetY = safeY
        case .eta:
            designerETAOffsetX = safeX; designerETAOffsetY = safeY
        case .timeLeft:
            designerTimeLeftOffsetX = safeX; designerTimeLeftOffsetY = safeY
        }
    }

    func resetDesignerOffset(_ component: HudMapDesignerComponent) {
        setDesignerOffset(component, x: 0, y: 0)
    }

    func resetAllDesignerOffsets() {
        for component in HudMapDesignerComponent.allCases {
            setDesignerOffset(component, x: 0, y: 0)
        }
    }

    func designerScale(for component: HudMapDesignerComponent) -> Double {
        switch component {
        case .speed: return speedScale
        case .speedLimit: return speedLimitSignHeightScale
        case .map: return centerScale
        case .turningStreet: return turningStreetScale
        case .maneuver: return maneuverArrowScale
        case .distance: return distanceScale
        case .lanes: return laneScale
        case .eta: return etaScale
        case .timeLeft: return timeLeftScale
        }
    }

    func setDesignerScale(_ component: HudMapDesignerComponent, value: Double) {
        switch component {
        case .speed: speedScale = min(1.80, max(0.50, value))
        case .speedLimit: speedLimitSignHeightScale = min(2.00, max(0.80, value))
        case .map: centerScale = min(1.45, max(0.60, value))
        case .turningStreet: turningStreetScale = min(1.60, max(0.60, value))
        case .maneuver: maneuverArrowScale = min(1.60, max(0.60, value))
        case .distance: distanceScale = min(1.60, max(0.60, value))
        case .lanes: laneScale = min(1.70, max(0.60, value))
        case .eta: etaScale = min(1.60, max(0.60, value))
        case .timeLeft: timeLeftScale = min(1.80, max(0.50, value))
        }
    }

    func resetWidgetOffsets() {
        leftOffsetX = 0
        leftOffsetY = 0
        centerOffsetX = 0
        centerOffsetY = 0
        rightOffsetX = 0
        rightOffsetY = 0
    }

    func resetRightComponentOffsets() {
        maneuverOffsetX = 0
        maneuverOffsetY = 0
        laneOffsetX = 0
        laneOffsetY = 0
        etaOffsetX = 0
        etaOffsetY = 0
    }

    func resetSpeedLimitStyling() {
        speedLimitSignHeightScale = 1.0
        speedLimitFontScale = 1.0
    }

    func resetRightStyling() {
        maneuverArrowScale = 1.0
        maneuverArrowThickness = 1.75
        turningStreetScale = 1.0
        distanceScale = 1.0
        laneScale = 1.0
        laneArrowThickness = 1.75
        laneArrowHeadScale = 1.35
        laneArrowBodyLength = 0.78
        laneSpacing = 3
        laneActiveEmphasis = 1.10
        laneInactiveGray = 0.40
        etaScale = 1.0
        streetToManeuverSpacing = 4
        maneuverToLaneSpacing = 4
        laneToETASpacing = 4
    }
}
