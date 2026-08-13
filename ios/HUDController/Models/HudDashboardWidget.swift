import Foundation

/// Exact SideWidget dashName values from the decompiled original application.
enum HudSideWidget: String, CaseIterable, Identifiable {
    case speed = "Speedo"
    case maxSpeed = "MaxSpeedo"
    case averageSpeed = "AvgSpeedo"
    case weather = "Weather"
    case time = "Time"
    case distance = "TraveledDistance"
    case cost = "Cost"
    case tripTime = "TripTime"
    case eta = "ETA"
    case empty = "None"
    case rpm = "RPM"
    case battery = "Battery"
    case fuel = "Gasoline"
    case fuelConsumption = "GasolineConsumption"
    case coolantTemperature = "EngineCoolantTemp"
    case oilTemperature = "EngineOilTemp"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speed: return "Speed"
        case .maxSpeed: return "Max speed"
        case .averageSpeed: return "Average speed"
        // We intentionally reserve the original firmware Weather widget
        // as the persistent Spotify/music display slot. The BLE/dashboard
        // token remains exactly "Weather"; only our iPhone UI label changes.
        case .weather: return "Music"
        case .time: return "Time"
        case .distance: return "Distance"
        case .cost: return "Trip cost"
        case .tripTime: return "Trip time"
        case .eta: return "ETA"
        case .empty: return "Empty"
        case .rpm: return "RPM"
        case .battery: return "Battery voltage"
        case .fuel: return "Fuel"
        case .fuelConsumption: return "Fuel consumption"
        case .coolantTemperature: return "Coolant temperature"
        case .oilTemperature: return "Engine oil temperature"
        }
    }
    var isMusicDisplaySlot: Bool {
        self == .weather
    }

}
