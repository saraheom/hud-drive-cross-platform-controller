import Foundation
import Vision
import UIKit

enum ExternalNavigationSource: String, Codable {
    case googleMaps = "Google Maps"
    case appleMaps = "Apple Maps"
    case unknown = "Unknown"
}

enum ExternalNavigationScreenState: String, Codable {
    case active
    case approachRoute
    case inactive
    case arrived
    case unknown
}

struct ParsedExternalNavigation: Equatable {
    var instruction: NavigationInstruction
    var rawText: String
    var isValidNavigation: Bool
    var confidence: Int
    var validationReason: String
    var source: ExternalNavigationSource = .unknown
    var screenState: ExternalNavigationScreenState = .unknown
    var originalDistanceText: String = ""
    var structuralConfidence: Int = 0
}

private struct OCRLine {
    let text: String
    let box: CGRect
    let candidates: [String]
}

enum ExternalNavigationOCRParser {
    static func recognize(_ image: UIImage) async throws -> ParsedExternalNavigation {
        guard let cgImage = image.cgImage else {
            throw NSError(
                domain: "HUDOCR",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Image has no CGImage"]
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var lines = observations.compactMap { observation -> OCRLine? in
                    let candidates = observation.topCandidates(5).map(\.string)
                    guard let first = candidates.first else { return nil }
                    // For navigation distance labels, a lower-ranked Vision
                    // candidate can preserve a decimal point that the top
                    // candidate drops (for example 2.3 mi -> 2 mi). Prefer the
                    // most information-preserving standalone distance candidate.
                    let preferred = preferredDistanceCandidate(candidates) ?? first
                    return OCRLine(text: preferred, box: observation.boundingBox, candidates: candidates)
                }

                // Vision order is usually sensible, but do not depend on it.
                // Normalized Vision boxes use a bottom-left origin.
                lines.sort {
                    let y0 = $0.box.midY
                    let y1 = $1.box.midY
                    if abs(y0 - y1) > 0.02 { return y0 > y1 }
                    return $0.box.minX < $1.box.minX
                }

                let raw = lines.map(\.text).joined(separator: "\n")
                let result = parse(
                    lines: lines.map(\.text),
                    rawText: raw,
                    image: image,
                    positionedLines: lines
                )
                continuation.resume(returning: result)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func preferredDistanceCandidate(_ candidates: [String]) -> String? {
        let matches = candidates.filter { isStandaloneDistance($0) }
        guard !matches.isEmpty else { return nil }
        return matches.sorted { a, b in
            let aDecimal = a.contains(".") ? 1 : 0
            let bDecimal = b.contains(".") ? 1 : 0
            if aDecimal != bDecimal { return aDecimal > bDecimal }
            return a.count > b.count
        }.first
    }

    static func parse(lines: [String], rawText: String) -> ParsedExternalNavigation {
        parse(lines: lines, rawText: rawText, image: nil, positionedLines: [])
    }

    private static func parse(
        lines: [String],
        rawText: String,
        image: UIImage?,
        positionedLines: [OCRLine]
    ) -> ParsedExternalNavigation {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let source = classifySource(cleaned)
        switch source {
        case .appleMaps:
            return AppleMapsOCRParser.parse(
                lines: cleaned,
                rawText: rawText,
                image: image,
                positionedLines: positionedLines
            )
        case .googleMaps:
            return GoogleMapsOCRParser.parseGoogle(
                lines: cleaned,
                rawText: rawText,
                positionedLines: positionedLines
            )
        case .unknown:
            // A normal Maps home screen is still useful because it tells the
            // navigation lifecycle to return to Freeride.
            let lower = cleaned.map { $0.lowercased() }
            if lower.contains(where: { $0.contains("google maps") }) ||
                (lower.contains(where: { $0.contains("search here") }) &&
                 lower.contains(where: { $0 == "explore" || $0.contains("contribute") })) {
                return inactive(source: .googleMaps, rawText: rawText, reason: "Google Maps home/map view")
            }
            if lower.contains(where: { $0.contains("apple maps") }) {
                return inactive(source: .appleMaps, rawText: rawText, reason: "Apple Maps home/map view")
            }
            return empty(rawText: rawText)
        }
    }

    private static func classifySource(_ lines: [String]) -> ExternalNavigationSource {
        let lower = lines.map { $0.lowercased() }
        var apple = 0
        var google = 0

        if lower.contains(where: { $0 == "end route" || $0.contains("end route") }) { apple += 70 }
        if lower.contains(where: { $0.contains("proceed to the route") || $0.contains("proceed to route") }) { apple += 80 }
        if lower.contains(where: { $0.contains("apple maps") }) { apple += 60 }

        let standaloneAppleDistances = lower.filter { isStandaloneDistance($0) }.count
        if standaloneAppleDistances >= 2 { apple += 25 }

        if lower.contains(where: { $0 == "directions" || $0.contains("directions") }) { google += 70 }
        if lower.contains(where: { $0.hasPrefix("turn ") || $0.hasPrefix("keep ") || $0.hasPrefix("take ") }) { google += 35 }
        if lower.contains(where: { $0.contains("google maps") }) { google += 60 }
        if lower.contains(where: { $0.hasPrefix("in ") && parseDistanceMeters($0) != nil }) { google += 30 }

        if apple >= 55 && apple > google + 10 { return .appleMaps }
        if google >= 55 && google > apple + 10 { return .googleMaps }

        // Apple route-list OCR can omit "End Route" if that button is below
        // the current capture crop. Repeated bare distances + road names are
        // still much more Apple-like than the Google text-instruction list.
        if standaloneAppleDistances >= 3 &&
            !lower.contains(where: { isExplicitGoogleManeuver($0) }) {
            return .appleMaps
        }

        return .unknown
    }

    fileprivate static func empty(rawText: String) -> ParsedExternalNavigation {
        ParsedExternalNavigation(
            instruction: NavigationInstruction(
                maneuver: .straight,
                distanceMeters: 0,
                primaryText: "No active navigation",
                streetName: ""
            ),
            rawText: rawText,
            isValidNavigation: false,
            confidence: 0,
            validationReason: "",
            source: .unknown,
            screenState: .unknown,
            structuralConfidence: 0
        )
    }

    fileprivate static func inactive(
        source: ExternalNavigationSource,
        rawText: String,
        reason: String
    ) -> ParsedExternalNavigation {
        ParsedExternalNavigation(
            instruction: NavigationInstruction(
                maneuver: .straight,
                distanceMeters: 0,
                primaryText: "Navigation inactive",
                streetName: ""
            ),
            rawText: rawText,
            isValidNavigation: false,
            confidence: 100,
            validationReason: reason,
            source: source,
            screenState: .inactive,
            structuralConfidence: 100
        )
    }

    fileprivate static func parseDistanceMeters(_ text: String) -> Int? {
        let s = text.lowercased()
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(ft|feet|mi|mile|miles)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let numberRange = Range(match.range(at: 1), in: s),
              let unitRange = Range(match.range(at: 2), in: s),
              let value = Double(s[numberRange]) else { return nil }

        let unit = String(s[unitRange])
        if unit == "ft" || unit == "feet" {
            // Preserve advertised feet across the integer-meter wire format.
            // Rounding down can turn 500 ft into ~499 ft and the HUD then
            // displays 400 ft. Ceil keeps boundary values on the intended side.
            return Int(ceil(value / 3.28084))
        }
        return Int((value * 1609.344).rounded())
    }

    fileprivate static func isStandaloneDistance(_ text: String) -> Bool {
        let s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[0-9]+(?:\.[0-9]+)?\s*(ft|feet|mi|mile|miles)$"#
        return (try? NSRegularExpression(pattern: pattern))?
            .firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    fileprivate static func isExplicitGoogleManeuver(_ text: String) -> Bool {
        let s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "turn left", "turn right", "keep left", "keep right",
            "take the", "take exit", "take a", "continue", "merge",
            "make a u-turn", "make a u turn", "u-turn", "uturn",
            "exit left", "exit right", "slight left", "slight right",
            "sharp left", "sharp right", "enter the roundabout",
            "at the roundabout"
        ]
        return prefixes.contains(where: s.hasPrefix)
    }

    fileprivate static func maneuverFromText(_ text: String) -> HudManeuver {
        let s = text.lowercased()
        if s.contains("arriv") || s.contains("destination") { return .destination }
        if s.contains("u-turn") || s.contains("uturn") { return .uTurn }
        if s.contains("keep left") { return .keepLeft }
        if s.contains("keep right") { return .keepRight }
        if s.contains("roundabout") { return .roundabout }
        if s.contains("exit") || s.contains("ramp") {
            if s.contains("left") { return .exitLeft }
            return .exitRight
        }
        if s.contains("slight left") { return .slightLeft }
        if s.contains("slight right") { return .slightRight }
        if s.contains("sharp left") { return .sharpLeft }
        if s.contains("sharp right") { return .sharpRight }
        if s.contains("left") { return .left }
        if s.contains("right") { return .right }
        return .straight
    }
}

enum GoogleMapsOCRParser {
    static func recognize(_ image: UIImage) async throws -> ParsedExternalNavigation {
        try await ExternalNavigationOCRParser.recognize(image)
    }

    static func parse(lines: [String], rawText: String) -> ParsedExternalNavigation {
        parseGoogle(lines: lines, rawText: rawText, positionedLines: [])
    }

    fileprivate static func parseGoogle(
        lines: [String],
        rawText: String,
        positionedLines: [OCRLine] = []
    ) -> ParsedExternalNavigation {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let lower = cleaned.map { $0.lowercased() }

        if lower.contains(where: {
            $0.contains("arrived") ||
            $0.contains("you have arrived") ||
            $0.contains("the destination is on your right") ||
            $0.contains("the destination is on your left") ||
            $0.hasPrefix("the destination is")
        }) {
            return ParsedExternalNavigation(
                instruction: NavigationInstruction(
                    maneuver: .destination,
                    distanceMeters: 0,
                    primaryText: "You have arrived",
                    streetName: ""
                ),
                rawText: rawText,
                isValidNavigation: true,
                confidence: 100,
                validationReason: "Google Maps arrival text",
                source: .googleMaps,
                screenState: .arrived,
                structuralConfidence: 100
            )
        }

        if lower.contains(where: { $0.contains("google maps") }) &&
            lower.contains(where: { $0.contains("search here") || $0 == "explore" }) &&
            !lower.contains(where: { $0.contains("directions") }) {
            return ExternalNavigationOCRParser.inactive(
                source: .googleMaps,
                rawText: rawText,
                reason: "Google Maps graphical/home view"
            )
        }

        // Google Maps near-destination card, e.g.
        // "In 0.4 mi / Home / Destination will be on the left".
        // This is APPROACHING the destination, not arrival.
        if let approachIndex = lower.firstIndex(where: {
            $0.contains("destination will be on the left") ||
            $0.contains("destination will be on the right")
        }) {
            let sideText = cleaned[approachIndex]
            let distanceCandidate = cleaned
                .prefix(approachIndex + 1)
                .reversed()
                .first(where: { ExternalNavigationOCRParser.parseDistanceMeters($0) != nil })
                ?? cleaned.first(where: { ExternalNavigationOCRParser.parseDistanceMeters($0) != nil })
                ?? ""

            if let meters = ExternalNavigationOCRParser.parseDistanceMeters(distanceCandidate),
               meters > 0 {
                let name = approachIndex > 0
                    ? cleaned[max(0, approachIndex - 1)]
                    : "Destination"
                return ParsedExternalNavigation(
                    instruction: NavigationInstruction(
                        maneuver: .destination,
                        distanceMeters: meters,
                        primaryText: sideText.lowercased().contains("left")
                            ? "Destination on left"
                            : "Destination on right",
                        streetName: name
                    ),
                    rawText: rawText,
                    isValidNavigation: true,
                    confidence: 100,
                    validationReason: "Google destination approach with remaining distance",
                    source: .googleMaps,
                    screenState: .active,
                    originalDistanceText: distanceCandidate,
                    structuralConfidence: 100
                )
            }
        }

        var selectedDistance = 0
        var originalDistance = ""
        var instructionLine = ""

        // Prefer spatial pairing on real OCR frames. Google can place several
        // complete maneuvers on the screen simultaneously; pairing merely by
        // flattened OCR order can attach the CURRENT distance to the NEXT
        // maneuver. The current card's distance sits immediately above its own
        // maneuver text.
        if !positionedLines.isEmpty,
           let pair = spatialCurrentGoogleCard(positionedLines) {
            selectedDistance = pair.meters
            originalDistance = pair.distanceText
            instructionLine = pair.instructionText
        }

        // Text-only / Vision fallback.
        if instructionLine.isEmpty {
            var bestIndex = Int.max
            for (i, line) in cleaned.enumerated() {
                guard let meters = ExternalNavigationOCRParser.parseDistanceMeters(line),
                      isNavigationDistanceLine(line) else { continue }

                let upper = min(cleaned.count - 1, i + 3)
                guard i < upper else { continue }

                for j in (i + 1)...upper
                where ExternalNavigationOCRParser.isExplicitGoogleManeuver(cleaned[j]) {
                    // Do not cross a second distance row. If another distance
                    // occurs before this maneuver, it belongs to a later card.
                    let crossedDistance = ((i + 1)..<j).contains {
                        isNavigationDistanceLine(cleaned[$0])
                    }
                    guard !crossedDistance else { continue }

                    if i < bestIndex {
                        bestIndex = i
                        selectedDistance = meters
                        originalDistance = line
                        instructionLine = cleaned[j]
                    }
                    break
                }
            }
        }

        if instructionLine.isEmpty {
            for (i, line) in cleaned.enumerated()
            where ExternalNavigationOCRParser.isExplicitGoogleManeuver(line) {
                let lowerIndex = max(0, i - 2)
                guard lowerIndex < i else { continue }
                for j in lowerIndex..<i {
                    if let meters = ExternalNavigationOCRParser.parseDistanceMeters(cleaned[j]),
                       isNavigationDistanceLine(cleaned[j]) {
                        selectedDistance = meters
                        originalDistance = cleaned[j]
                        instructionLine = line
                        break
                    }
                }
                if !instructionLine.isEmpty { break }
            }
        }

        let maneuver = ExternalNavigationOCRParser.maneuverFromText(instructionLine)
        let street = streetFromInstruction(instructionLine)
        let primary = compactPrimaryInstruction(instructionLine, maneuver: maneuver)

        var confidence = 0
        var reasons: [String] = []
        if lower.contains(where: { $0.contains("directions") }) {
            confidence += 25
            reasons.append("Directions layout")
        }
        if !instructionLine.isEmpty {
            confidence += 40
            reasons.append("explicit maneuver")
        }
        if selectedDistance > 0 {
            confidence += 30
            reasons.append("paired distance")
        }
        if !street.isEmpty {
            confidence += 5
            reasons.append("road name")
        }

        let rejectedUIWords = [
            "screen capture", "keep screen", "automatically send",
            "saved screenshot", "frames ocr", "brightness", "spotify",
            "reconnect", "widget", "notification", "bluetooth"
        ]
        let containsOwnUI = rejectedUIWords.contains {
            instructionLine.lowercased().contains($0)
        }
        if containsOwnUI {
            confidence = 0
            reasons = ["HUD Controller UI text"]
        }

        let valid = confidence >= 75 &&
            selectedDistance > 0 &&
            !instructionLine.isEmpty &&
            !containsOwnUI

        return ParsedExternalNavigation(
            instruction: NavigationInstruction(
                maneuver: maneuver,
                distanceMeters: selectedDistance,
                primaryText: primary,
                streetName: street
            ),
            rawText: rawText,
            isValidNavigation: valid,
            confidence: confidence,
            validationReason: reasons.joined(separator: ", "),
            source: .googleMaps,
            screenState: valid ? .active : .unknown,
            originalDistanceText: originalDistance,
            structuralConfidence: lower.contains(where: { $0.contains("directions") }) ? 100 : confidence
        )
    }

    private static func isNavigationDistanceLine(_ text: String) -> Bool {
        let s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard ExternalNavigationOCRParser.parseDistanceMeters(s) != nil else { return false }
        if s.hasPrefix("in ") || s.hasPrefix("then ") { return true }
        return ExternalNavigationOCRParser.isStandaloneDistance(s)
    }

    private static func streetFromInstruction(_ text: String) -> String {
        let lower = text.lowercased()
        for marker in [" onto ", " toward ", " towards ", " to stay on ", " to "] {
            if let range = lower.range(of: marker) {
                return String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func compactPrimaryInstruction(
        _ text: String,
        maneuver: HudManeuver
    ) -> String {
        // Keep the maneuver line short enough for the physical HUD. Context
        // such as "after the gas station (on the left)" is useful in Maps but
        // causes the HUD renderer to truncate the actual road name.
        switch maneuver {
        case .left: return "Turn left"
        case .right: return "Turn right"
        case .slightLeft: return "Slight left"
        case .slightRight: return "Slight right"
        case .sharpLeft: return "Sharp left"
        case .sharpRight: return "Sharp right"
        case .keepLeft: return "Keep left"
        case .keepRight: return "Keep right"
        case .exitLeft: return "Exit left"
        case .exitRight: return "Exit right"
        case .uTurn: return "U-turn"
        case .roundabout: return "Roundabout"
        case .destination: return "Destination"
        case .straight: return "Continue straight"
        }
    }

    private static func spatialCurrentGoogleCard(
        _ lines: [OCRLine]
    ) -> (meters: Int, distanceText: String, instructionText: String)? {
        let distances = lines.compactMap { line -> (OCRLine, Int)? in
            guard isNavigationDistanceLine(line.text),
                  let meters = ExternalNavigationOCRParser.parseDistanceMeters(line.text)
            else { return nil }
            return (line, meters)
        }
        .sorted { $0.0.box.midY > $1.0.box.midY }

        for (distance, meters) in distances {
            // Vision normalized boxes have bottom-left origin. Instruction
            // text is visually BELOW the distance, therefore lower midY.
            let candidates = lines.filter {
                ExternalNavigationOCRParser.isExplicitGoogleManeuver($0.text) &&
                $0.box.midY < distance.box.midY &&
                (distance.box.midY - $0.box.midY) < 0.13
            }
            .sorted {
                abs(distance.box.midY - $0.box.midY) <
                abs(distance.box.midY - $1.box.midY)
            }

            if let instruction = candidates.first {
                return (meters, distance.text, instruction.text)
            }
        }

        return nil
    }
}

private enum AppleMapsOCRParser {
    static func parse(
        lines: [String],
        rawText: String,
        image: UIImage?,
        positionedLines: [OCRLine]
    ) -> ParsedExternalNavigation {
        let lower = lines.map { $0.lowercased() }

        if lower.contains(where: {
            $0.contains("arrived") ||
            $0.contains("you have arrived") ||
            $0.contains("the destination is on your right") ||
            $0.contains("the destination is on your left") ||
            $0.hasPrefix("the destination is")
        }) {
            return ParsedExternalNavigation(
                instruction: NavigationInstruction(
                    maneuver: .destination,
                    distanceMeters: 0,
                    primaryText: "You have arrived",
                    streetName: ""
                ),
                rawText: rawText,
                isValidNavigation: true,
                confidence: 100,
                validationReason: "Apple Maps arrival text",
                source: .appleMaps,
                screenState: .arrived,
                structuralConfidence: 100
            )
        }

        let proceed = lower.contains {
            $0.contains("proceed to the route") ||
            $0.contains("proceed to route")
        }
        let endRoute = lower.contains { $0.contains("end route") }

        if proceed {
            return ParsedExternalNavigation(
                instruction: NavigationInstruction(
                    maneuver: .straight,
                    distanceMeters: 0,
                    primaryText: "Proceed to the route",
                    streetName: ""
                ),
                rawText: rawText,
                isValidNavigation: true,
                confidence: 100,
                validationReason: "Apple Maps Proceed to route",
                source: .appleMaps,
                screenState: .approachRoute,
                structuralConfidence: endRoute ? 100 : 90
            )
        }

        if lower.contains(where: { $0.contains("apple maps") }) && !endRoute {
            return ExternalNavigationOCRParser.inactive(
                source: .appleMaps,
                rawText: rawText,
                reason: "Apple Maps graphical/home view"
            )
        }

        // Find the first/top standalone distance. On Apple Maps the following
        // OCR line is the street/route text for the same card.
        var distanceIndex: Int?
        var distanceText = ""
        var distanceMeters = 0

        for (i, line) in lines.enumerated() {
            if ExternalNavigationOCRParser.isStandaloneDistance(line),
               let meters = ExternalNavigationOCRParser.parseDistanceMeters(line) {
                distanceIndex = i
                distanceText = line
                distanceMeters = meters
                break
            }
        }

        guard let index = distanceIndex, distanceMeters > 0 else {
            return ParsedExternalNavigation(
                instruction: NavigationInstruction(
                    maneuver: .straight,
                    distanceMeters: 0,
                    primaryText: "Apple Maps navigation",
                    streetName: ""
                ),
                rawText: rawText,
                isValidNavigation: false,
                confidence: endRoute ? 55 : 0,
                validationReason: endRoute ? "Apple route list but no first distance" : "",
                source: .appleMaps,
                screenState: endRoute ? .active : .unknown,
                structuralConfidence: endRoute ? 100 : 0
            )
        }

        var road = ""
        var shieldNumber: String?
        if index + 1 < lines.count {
            for j in (index + 1)..<min(lines.count, index + 6) {
                let candidate = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                let l = candidate.lowercased()

                if l.contains("end route") ||
                    ExternalNavigationOCRParser.isStandaloneDistance(candidate) {
                    break
                }

                if let shield = extractRouteShieldPrefix(candidate) {
                    if shieldNumber == nil {
                        shieldNumber = shield.number
                    }

                    // If OCR merged the shield with useful road/direction text,
                    // keep the remainder. If this is shield-only (`13`, `/13`,
                    // `{13}`), continue to the next OCR line rather than
                    // prematurely setting the road to garbage such as `/13`.
                    if !shield.remainder.isEmpty {
                        road = shield.remainder
                        break
                    }
                    continue
                }

                if !candidate.isEmpty {
                    let cleanedRoad = stripRouteShieldOCR(candidate)
                    if !cleanedRoad.isEmpty {
                        road = cleanedRoad
                        break
                    }
                }
            }
        }

        if let shieldNumber {
            let shieldLabel = routeShieldLabel(
                number: shieldNumber,
                image: image,
                positionedLines: positionedLines
            )
            if !shieldLabel.isEmpty {
                road = road.isEmpty ? shieldLabel : "\(shieldLabel) \(road)"
            }
        }

        let maneuver: HudManeuver
        if let image,
           let positionedDistance = positionedLines.first(where: {
               $0.text.caseInsensitiveCompare(distanceText) == .orderedSame
           }) {
            maneuver = AppleManeuverIconClassifier.classify(
                image: image,
                distanceBox: positionedDistance.box
            )
        } else {
            // Text-only unit tests cannot see Apple's graphical turn arrow.
            maneuver = .straight
        }

        var confidence = 60
        if endRoute { confidence += 25 }
        if !road.isEmpty { confidence += 15 }

        return ParsedExternalNavigation(
            instruction: NavigationInstruction(
                maneuver: maneuver,
                distanceMeters: distanceMeters,
                primaryText: maneuver.label,
                streetName: road
            ),
            rawText: rawText,
            isValidNavigation: confidence >= 75,
            confidence: confidence,
            validationReason: "Apple route card, first distance, road=\(!road.isEmpty)",
            source: .appleMaps,
            screenState: .active,
            originalDistanceText: distanceText,
            structuralConfidence: endRoute ? 100 : confidence
        )
    }


    private static func extractRouteShieldPrefix(
        _ text: String
    ) -> (number: String, remainder: String)? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Common Vision outputs observed from Apple route shields:
        // "13", "/13", "{13}", "(13)", "[13]", "US 13", "13 N 38th St".
        let patterns = [
            #"^\s*(?:US|U\.?S\.?|I|IS|INTERSTATE)?\s*[-/]?\s*[\{\[\(]?\s*(\d{1,3})\s*[\}\]\)]?\s*(.*)$"#,
            #"^\s*[/\\|]?\s*(\d{1,3})\s*(.*)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }

            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = regex.firstMatch(in: value, options: [], range: range),
                  match.numberOfRanges >= 3,
                  let numberRange = Range(match.range(at: 1), in: value),
                  let remainderRange = Range(match.range(at: 2), in: value)
            else { continue }

            let number = String(value[numberRange])
            let remainder = String(value[remainderRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Avoid interpreting ordinary street numbers like "4442 Ridge Ave"
            // as route shields. Shield numbers are short and are either alone,
            // preceded by shield punctuation/prefixes, or followed by a
            // cardinal direction / road text in the Apple route-card pattern.
            let explicitShieldMarker =
                value.range(of: #"^\s*(?:US|U\.?S\.?|I|IS|INTERSTATE|[/\\|{\[(])"#,
                            options: [.regularExpression, .caseInsensitive]) != nil
            let shieldOnly = remainder.isEmpty
            let directionalRemainder =
                remainder.range(of: #"^(?:N|S|E|W|North|South|East|West)\b"#,
                                options: [.regularExpression, .caseInsensitive]) != nil

            if explicitShieldMarker || shieldOnly || directionalRemainder {
                return (number, remainder)
            }
        }

        return nil
    }

    private static func routeShieldLabel(
        number: String,
        image: UIImage?,
        positionedLines: [OCRLine]
    ) -> String {
        // If Vision itself recognized a route prefix, preserve it.
        let all = positionedLines.map(\.text).joined(separator: " ")
        if all.range(of: #"\bI[- ]?\#(number)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "I-\(number)"
        }
        if all.range(of: #"\bUS[- ]?\#(number)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return "US \(number)"
        }

        guard let image,
              let cg = image.cgImage,
              let numberLine = positionedLines.first(where: {
                  $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == number
              }) else {
            return "US \(number)"
        }

        // Interstate shields in Apple Maps are normally colored; U.S. route
        // shields are grayscale/white. Sample the shield around the OCR number.
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let b = numberLine.box
        let x = max(0, b.minX * w - b.width * w * 0.55)
        let y = max(0, (1 - b.maxY) * h - b.height * h * 0.45)
        let rw = min(w - x, b.width * w * 2.1)
        let rh = min(h - y, b.height * h * 1.9)
        let rect = CGRect(x: x, y: y, width: rw, height: rh).integral

        guard rect.width > 5, rect.height > 5,
              let crop = cg.cropping(to: rect),
              let saturation = averageSaturation(crop) else {
            return "US \(number)"
        }

        return saturation > 0.18 ? "I-\(number)" : "US \(number)"
    }

    private static func averageSaturation(_ image: CGImage) -> Double? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sum = 0.0
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let r = Double(bytes[i]) / 255.0
            let g = Double(bytes[i + 1]) / 255.0
            let b = Double(bytes[i + 2]) / 255.0
            let maxv = max(r, g, b)
            let minv = min(r, g, b)
            guard maxv > 0.15 else { continue }
            sum += maxv == 0 ? 0 : (maxv - minv) / maxv
            count += 1
        }
        return count > 0 ? sum / Double(count) : nil
    }

    private static func stripRouteShieldOCR(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // OCR often returns the route-shield number before the actual road.
        value = value.replacingOccurrences(
            of: #"^\s*[\{\[\(]?\s*(?:US|I|IS|INTERSTATE)?[- ]?\d{1,3}\s*[\}\]\)]?\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum AppleManeuverIconClassifier {
    static func classify(image: UIImage, distanceBox: CGRect) -> HudManeuver {
        guard let cg = image.cgImage else { return .straight }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)

        // The maneuver icon is immediately left of the first distance label.
        // Vision box coordinates are normalized with bottom-left origin.
        let distanceTop = (1 - distanceBox.maxY) * height
        let distanceBottom = (1 - distanceBox.minY) * height
        let centerY = (distanceTop + distanceBottom) * 0.5
        let cropHeight = max(90, (distanceBottom - distanceTop) * 2.7)
        let cropWidth = min(width * 0.26, max(120, distanceBox.minX * width * 0.95))

        // Apple lane-guidance cards are structurally different: several gray
        // arrows span the card and the recommended lane is the single bright
        // white glyph, often to the RIGHT of the distance text. The old
        // left-of-distance crop could therefore classify the wrong lane.
        if let lane = classifyHighlightedLaneArrow(
            cgImage: cg,
            distanceTop: distanceTop,
            distanceHeight: max(20, distanceBottom - distanceTop)
        ) {
            return lane
        }

        var rect = CGRect(
            x: 15,
            y: centerY - cropHeight * 0.5,
            width: max(60, cropWidth - 15),
            height: cropHeight
        )
        rect = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 20, rect.height > 20,
              let crop = cg.cropping(to: rect.integral),
              let data = thresholdedPixels(crop) else { return .straight }

        let w = data.width
        let h = data.height
        guard w > 0, h > 0, data.points.count > 20 else { return .straight }

        // IMPORTANT: classify ONLY the connected maneuver glyph. The previous
        // versions measured every bright pixel in this crop. Depending on the
        // Vision distance bounding box, fragments of the white distance label
        // could enter the crop and completely reverse the left/right geometry.
        guard let glyph = dominantArrowComponent(from: data),
              glyph.count > 20 else { return .straight }

        let xs = glyph.map(\.x)
        let ys = glyph.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return .straight }

        let bw = max(1, maxX - minX + 1)
        let bh = max(1, maxY - minY + 1)

        // Straight arrows are tall and centered. Test this before left/right.
        if Double(bh) > Double(bw) * 1.28 {
            return .straight
        }

        // v62: classify the ISOLATED maneuver glyph by its extreme-edge
        // geometry. This is the invariant visible in the supplied Apple Maps
        // screenshots:
        //
        // LEFT turn:
        //   left extreme  = narrow arrow tip (short span / less mass)
        //   right extreme = tall vertical stem / bend
        //
        // RIGHT turn:
        //   right extreme = narrow arrow tip
        //   left extreme  = tall vertical stem / bend
        //
        // Because this operates after connected-component isolation, distance
        // text can no longer contaminate the measurement.
        let edgeWidth = max(3, Int(Double(bw) * 0.18))
        let leftEdge = glyph.filter { $0.x <= minX + edgeWidth }
        let rightEdge = glyph.filter { $0.x >= maxX - edgeWidth }

        func verticalSpan(_ points: [(x: Int, y: Int)]) -> Int {
            guard let lo = points.map(\.y).min(),
                  let hi = points.map(\.y).max() else { return 0 }
            return hi - lo + 1
        }

        let leftCount = leftEdge.count
        let rightCount = rightEdge.count
        let leftSpan = verticalSpan(leftEdge)
        let rightSpan = verticalSpan(rightEdge)

        let leftIsTip =
            Double(leftCount) < Double(max(1, rightCount)) * 0.72 &&
            Double(leftSpan) < Double(max(1, rightSpan)) * 0.78

        let rightIsTip =
            Double(rightCount) < Double(max(1, leftCount)) * 0.72 &&
            Double(rightSpan) < Double(max(1, leftSpan)) * 0.78

        if leftIsTip { return .left }
        if rightIsTip { return .right }

        // Secondary fallback using only the vertical-span asymmetry. This is
        // intentionally conservative so anti-aliasing doesn't flip a turn.
        if Double(leftSpan) < Double(max(1, rightSpan)) * 0.62 {
            return .left
        }
        if Double(rightSpan) < Double(max(1, leftSpan)) * 0.62 {
            return .right
        }

        return .straight
    }

    /// Extract connected bright-pixel components and choose the one most
    /// likely to be the Apple maneuver glyph. This makes classification
    /// independent of small OCR distance-box shifts and excludes distance
    /// digits/text that happen to enter the crop.
    private static func dominantArrowComponent(
        from pixels: PixelSet
    ) -> [(x: Int, y: Int)]? {
        guard pixels.width > 0, pixels.height > 0 else { return nil }

        let width = pixels.width
        let height = pixels.height
        var occupied = [Bool](repeating: false, count: width * height)
        for point in pixels.points where
            point.x >= 0 && point.x < width && point.y >= 0 && point.y < height {
            occupied[point.y * width + point.x] = true
        }

        var visited = [Bool](repeating: false, count: width * height)
        var components: [[(x: Int, y: Int)]] = []
        let neighborOffsets = [
            (-1, -1), (0, -1), (1, -1),
            (-1,  0),          (1,  0),
            (-1,  1), (0,  1), (1,  1)
        ]

        for seed in pixels.points {
            let seedIndex = seed.y * width + seed.x
            guard seedIndex >= 0, seedIndex < visited.count,
                  !visited[seedIndex] else { continue }

            var queue = [seed]
            var head = 0
            visited[seedIndex] = true
            var component: [(x: Int, y: Int)] = []

            while head < queue.count {
                let current = queue[head]
                head += 1
                component.append(current)

                for (dx, dy) in neighborOffsets {
                    let nx = current.x + dx
                    let ny = current.y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let index = ny * width + nx
                    guard occupied[index], !visited[index] else { continue }
                    visited[index] = true
                    queue.append((x: nx, y: ny))
                }
            }

            if component.count >= 12 {
                components.append(component)
            }
        }

        // The maneuver icon is a large connected white glyph on the left side
        // of the card. Prefer substantial/tall components and penalize anything
        // whose center is in the far-right portion of this icon crop (normally
        // leaked distance text).
        return components.max { lhs, rhs in
            componentArrowScore(lhs, cropWidth: width) <
            componentArrowScore(rhs, cropWidth: width)
        }
    }

    private static func componentArrowScore(
        _ component: [(x: Int, y: Int)],
        cropWidth: Int
    ) -> Double {
        let xs = component.map(\.x)
        let ys = component.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return 0 }

        let bw = maxX - minX + 1
        let bh = maxY - minY + 1
        let centerX = Double(minX + maxX) / 2.0
        let rightPenalty = centerX > Double(cropWidth) * 0.72 ? 0.18 : 1.0
        let shapeBonus = Double(min(bw, bh)) / Double(max(1, max(bw, bh))) + 0.55

        return Double(component.count) * shapeBonus * rightPenalty
    }

    private static func classifyHighlightedLaneArrow(
        cgImage: CGImage,
        distanceTop: CGFloat,
        distanceHeight: CGFloat
    ) -> HudManeuver? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        // Search the horizontal band immediately above the first distance.
        // This excludes the white distance digits themselves.
        var rect = CGRect(
            x: width * 0.05,
            y: max(0, distanceTop - max(150, distanceHeight * 3.2)),
            width: width * 0.90,
            height: max(90, min(150, distanceHeight * 2.5))
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 40, rect.height > 40,
              let crop = cgImage.cropping(to: rect.integral),
              let pixels = thresholdedPixels(crop),
              pixels.points.count > 35 else { return nil }

        let xs = pixels.points.map(\.x)
        let ys = pixels.points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }

        let bw = maxX - minX + 1
        let bh = maxY - minY + 1
        let centerX = Double(minX + maxX) / 2.0 / Double(max(1, pixels.width))

        // A normal single-turn card keeps its icon on the far left. Lane
        // guidance is recognized only when the highlighted glyph occupies the
        // middle/right portion of this full-width band.
        guard centerX > 0.28 else { return nil }

        if Double(bh) > Double(bw) * 1.15 { return .straight }

        let midX = Double(minX + maxX) / 2.0
        var leftTip = 0
        var rightTip = 0
        for point in pixels.points {
            if Double(point.x) < midX - Double(bw) * 0.22 { leftTip += 1 }
            if Double(point.x) > midX + Double(bw) * 0.22 { rightTip += 1 }
        }
        if rightTip > leftTip * 6 / 5 { return .right }
        if leftTip > rightTip * 6 / 5 { return .left }
        return .straight
    }

    private struct PixelSet {
        let width: Int
        let height: Int
        let points: [(x: Int, y: Int)]
    }

    private static func thresholdedPixels(_ image: CGImage) -> PixelSet? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &bytes,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var points: [(Int, Int)] = []
        points.reserveCapacity(w * h / 8)

        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Int(bytes[i])
                let g = Int(bytes[i + 1])
                let b = Int(bytes[i + 2])

                // Apple Maps route list uses a very bright maneuver glyph on a
                // dark card. This threshold intentionally ignores gray road text.
                if r > 205 && g > 205 && b > 205 {
                    points.append((x, y))
                }
            }
        }

        return PixelSet(width: w, height: h, points: points)
    }
}
