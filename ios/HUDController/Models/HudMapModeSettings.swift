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
}
