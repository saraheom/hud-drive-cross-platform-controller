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

/// Persisted presentation controls for the custom Map Mode renderer.
///
/// These values affect only the custom map-mode composition. They do not alter
/// the stock Freeride/Navigation dashboard widget configuration.
@MainActor
@Observable
final class HudMapModeSettings {
    private let defaults = UserDefaults.standard

    var leftScale: Double { didSet { defaults.set(leftScale, forKey: "HUD.MapMode.leftScale") } }
    var centerScale: Double { didSet { defaults.set(centerScale, forKey: "HUD.MapMode.centerScale") } }
    var rightScale: Double { didSet { defaults.set(rightScale, forKey: "HUD.MapMode.rightScale") } }

    // Physical 480×240 canvas calibration. Offsets are stored in final-render pixels.
    var leftOffsetX: Double { didSet { defaults.set(leftOffsetX, forKey: "HUD.MapMode.leftOffsetX") } }
    var leftOffsetY: Double { didSet { defaults.set(leftOffsetY, forKey: "HUD.MapMode.leftOffsetY") } }
    var centerOffsetX: Double { didSet { defaults.set(centerOffsetX, forKey: "HUD.MapMode.centerOffsetX") } }
    var centerOffsetY: Double { didSet { defaults.set(centerOffsetY, forKey: "HUD.MapMode.centerOffsetY") } }
    var rightOffsetX: Double { didSet { defaults.set(rightOffsetX, forKey: "HUD.MapMode.rightOffsetX") } }
    var rightOffsetY: Double { didSet { defaults.set(rightOffsetY, forKey: "HUD.MapMode.rightOffsetY") } }

    // Right-side turn/lane/ETA fine tuning. These affect only the rendered JPEG;
    // they do not alter Route Guidance parsing or the U2W transport.
    var maneuverArrowScale: Double { didSet { defaults.set(maneuverArrowScale, forKey: "HUD.MapMode.maneuverArrowScale") } }
    var maneuverArrowThickness: Double { didSet { defaults.set(maneuverArrowThickness, forKey: "HUD.MapMode.maneuverArrowThickness") } }
    var maneuverOffsetX: Double { didSet { defaults.set(maneuverOffsetX, forKey: "HUD.MapMode.maneuverOffsetX") } }
    var maneuverOffsetY: Double { didSet { defaults.set(maneuverOffsetY, forKey: "HUD.MapMode.maneuverOffsetY") } }
    var turningStreetScale: Double { didSet { defaults.set(turningStreetScale, forKey: "HUD.MapMode.turningStreetScale") } }
    var distanceScale: Double { didSet { defaults.set(distanceScale, forKey: "HUD.MapMode.distanceScale") } }

    var laneScale: Double { didSet { defaults.set(laneScale, forKey: "HUD.MapMode.laneScale") } }
    var laneArrowThickness: Double { didSet { defaults.set(laneArrowThickness, forKey: "HUD.MapMode.laneArrowThickness") } }
    var laneSpacing: Double { didSet { defaults.set(laneSpacing, forKey: "HUD.MapMode.laneSpacing") } }
    var laneActiveEmphasis: Double { didSet { defaults.set(laneActiveEmphasis, forKey: "HUD.MapMode.laneActiveEmphasis") } }
    var laneOffsetX: Double { didSet { defaults.set(laneOffsetX, forKey: "HUD.MapMode.laneOffsetX") } }
    var laneOffsetY: Double { didSet { defaults.set(laneOffsetY, forKey: "HUD.MapMode.laneOffsetY") } }

    var etaScale: Double { didSet { defaults.set(etaScale, forKey: "HUD.MapMode.etaScale") } }
    var etaOffsetX: Double { didSet { defaults.set(etaOffsetX, forKey: "HUD.MapMode.etaOffsetX") } }
    var etaOffsetY: Double { didSet { defaults.set(etaOffsetY, forKey: "HUD.MapMode.etaOffsetY") } }

    // Real U2W 800×480 MainVideo crop calibration. Values are expressed in the
    // center widget's local coordinates so they remain independent of widget size.
    var sourceMapZoom: Double { didSet { defaults.set(sourceMapZoom, forKey: "HUD.MapMode.sourceMapZoom") } }
    var sourceMapOffsetX: Double { didSet { defaults.set(sourceMapOffsetX, forKey: "HUD.MapMode.sourceMapOffsetX") } }
    var sourceMapOffsetY: Double { didSet { defaults.set(sourceMapOffsetY, forKey: "HUD.MapMode.sourceMapOffsetY") } }

    var showSpeed: Bool { didSet { defaults.set(showSpeed, forKey: "HUD.MapMode.showSpeed") } }
    var showSpeedLimit: Bool { didSet { defaults.set(showSpeedLimit, forKey: "HUD.MapMode.showSpeedLimit") } }
    var showMap: Bool { didSet { defaults.set(showMap, forKey: "HUD.MapMode.showMap") } }
    var showTurningStreet: Bool { didSet { defaults.set(showTurningStreet, forKey: "HUD.MapMode.showTurningStreet") } }
    var showManeuver: Bool { didSet { defaults.set(showManeuver, forKey: "HUD.MapMode.showManeuver") } }
    var showDistance: Bool { didSet { defaults.set(showDistance, forKey: "HUD.MapMode.showDistance") } }
    var showLaneGuidance: Bool { didSet { defaults.set(showLaneGuidance, forKey: "HUD.MapMode.showLaneGuidance") } }
    var showETA: Bool { didSet { defaults.set(showETA, forKey: "HUD.MapMode.showETA") } }
    var showTimeLeft: Bool { didSet { defaults.set(showTimeLeft, forKey: "HUD.MapMode.showTimeLeft") } }

    var nativeOBDSpeedOverlayExperiment: Bool {
        didSet { defaults.set(nativeOBDSpeedOverlayExperiment, forKey: "HUD.MapMode.nativeOBDSpeedOverlayExperiment") }
    }

    var mapAppearance: HudMapAppearance {
        didSet { defaults.set(mapAppearance.rawValue, forKey: "HUD.MapMode.mapAppearance") }
    }

    init() {
        let store = UserDefaults.standard

        func bool(_ key: String, default fallback: Bool) -> Bool {
            store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
        }

        func double(_ key: String, default fallback: Double) -> Double {
            store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
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

        maneuverArrowScale = min(1.40, max(0.80, double("HUD.MapMode.maneuverArrowScale", default: 1.0)))
        maneuverArrowThickness = min(2.50, max(1.00, double("HUD.MapMode.maneuverArrowThickness", default: 1.75)))
        maneuverOffsetX = min(12, max(-12, double("HUD.MapMode.maneuverOffsetX", default: 0)))
        maneuverOffsetY = min(10, max(-10, double("HUD.MapMode.maneuverOffsetY", default: 0)))
        turningStreetScale = min(1.30, max(0.80, double("HUD.MapMode.turningStreetScale", default: 1.0)))
        distanceScale = min(1.30, max(0.80, double("HUD.MapMode.distanceScale", default: 1.0)))

        laneScale = min(1.50, max(0.80, double("HUD.MapMode.laneScale", default: 1.0)))
        laneArrowThickness = min(2.50, max(1.00, double("HUD.MapMode.laneArrowThickness", default: 1.75)))
        laneSpacing = min(8, max(1, double("HUD.MapMode.laneSpacing", default: 3)))
        laneActiveEmphasis = min(1.35, max(1.00, double("HUD.MapMode.laneActiveEmphasis", default: 1.10)))
        laneOffsetX = min(12, max(-12, double("HUD.MapMode.laneOffsetX", default: 0)))
        laneOffsetY = min(10, max(-10, double("HUD.MapMode.laneOffsetY", default: 0)))

        etaScale = min(1.40, max(0.80, double("HUD.MapMode.etaScale", default: 1.0)))
        etaOffsetX = min(12, max(-12, double("HUD.MapMode.etaOffsetX", default: 0)))
        etaOffsetY = min(10, max(-10, double("HUD.MapMode.etaOffsetY", default: 0)))
        // Defaults are tuned to the physical 800×480 Google Maps / CarPlay
        // Dashboard frame from the v8.10 dump: map region is primarily left of
        // the media pane, after the vertical CarPlay launcher rail.
        sourceMapZoom = min(2.60, max(0.80, double("HUD.MapMode.sourceMapZoom", default: 1.55)))
        sourceMapOffsetX = min(1.0, max(-1.0, double("HUD.MapMode.sourceMapOffsetX", default: 0.22)))
        sourceMapOffsetY = min(1.0, max(-1.0, double("HUD.MapMode.sourceMapOffsetY", default: 0.0)))

        showSpeed = bool("HUD.MapMode.showSpeed", default: true)
        showSpeedLimit = bool("HUD.MapMode.showSpeedLimit", default: true)
        showMap = bool("HUD.MapMode.showMap", default: true)
        showTurningStreet = bool("HUD.MapMode.showTurningStreet", default: true)
        showManeuver = bool("HUD.MapMode.showManeuver", default: true)
        showDistance = bool("HUD.MapMode.showDistance", default: true)
        showLaneGuidance = bool("HUD.MapMode.showLaneGuidance", default: true)
        showETA = bool("HUD.MapMode.showETA", default: true)
        showTimeLeft = bool("HUD.MapMode.showTimeLeft", default: true)
        nativeOBDSpeedOverlayExperiment = bool("HUD.MapMode.nativeOBDSpeedOverlayExperiment", default: true)

        let raw = store.string(forKey: "HUD.MapMode.mapAppearance") ?? HudMapAppearance.followSource.rawValue
        mapAppearance = HudMapAppearance(rawValue: raw) ?? .followSource
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

    func resetRightStyling() {
        maneuverArrowScale = 1.0
        maneuverArrowThickness = 1.75
        turningStreetScale = 1.0
        distanceScale = 1.0
        laneScale = 1.0
        laneArrowThickness = 1.75
        laneSpacing = 3
        laneActiveEmphasis = 1.10
        etaScale = 1.0
    }
}
