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
        var roadOCRLine: OCRLine?
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
                        roadOCRLine = positionedLines.first(where: {
                            $0.text.caseInsensitiveCompare(candidate) == .orderedSame
                        })
                        break
                    }
                    continue
                }

                if !candidate.isEmpty {
                    let cleanedRoad = stripRouteShieldOCR(candidate)
                    if !cleanedRoad.isEmpty {
                        road = cleanedRoad
                        roadOCRLine = positionedLines.first(where: {
                            $0.text.caseInsensitiveCompare(candidate) == .orderedSame
                        })
                        break
                    }
                }
            }
        }

        // Some Apple screenshots produce only "North"/"South" from the
        // first OCR pass even though a route shield is visibly present. In
        // that case, run one narrow high-accuracy Vision request over the
        // shield region immediately to the left of the road/direction line.
        if shieldNumber == nil,
           let image,
           let roadOCRLine,
           let recovered = recoverRouteShieldNumber(
               image: image,
               roadLine: roadOCRLine
           ) {
            shieldNumber = recovered
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


    private static func recoverRouteShieldNumber(
        image: UIImage,
        roadLine: OCRLine
    ) -> String? {
        guard let cg = image.cgImage else { return nil }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let b = roadLine.box

        // Apple route shields are immediately left of the road/direction text,
        // but the exact spacing varies with short strings such as "North".
        // Try several increasingly wide crops rather than betting on one ROI.
        let leftExpansions: [CGFloat] = [0.12, 0.17, 0.22, 0.27]

        for expansion in leftExpansions {
            let normalizedLeft = max(0, b.minX - expansion)
            let normalizedRight = min(1, b.minX + 0.012)
            let halfHeight = max(0.035, b.height * 1.25)
            let normalizedBottom = max(0, b.midY - halfHeight)
            let normalizedTop = min(1, b.midY + halfHeight)

            var rect = CGRect(
                x: normalizedLeft * width,
                y: (1 - normalizedTop) * height,
                width: (normalizedRight - normalizedLeft) * width,
                height: (normalizedTop - normalizedBottom) * height
            ).integral
            rect = rect.intersection(
                CGRect(x: 0, y: 0, width: width, height: height)
            )

            guard rect.width > 14,
                  rect.height > 14,
                  let crop = cg.cropping(to: rect),
                  let enlarged = upscaleShieldCrop(crop, scale: 4)
            else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.025
            request.recognitionLanguages = ["en-US"]
            request.customWords = [
                "1", "13", "76",
                "US 1", "US 13", "I-76"
            ]

            let handler = VNImageRequestHandler(cgImage: enlarged, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continue
            }

            for observation in request.results ?? [] {
                for candidate in observation.topCandidates(10) {
                    let text = candidate.string
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if let number = extractShortShieldNumber(text) {
                        return number
                    }
                }
            }
        }

        // Vision occasionally ignores the single digit "1" in Apple's
        // US-route shield entirely (the full OCR line becomes only "North").
        // Use a conservative visual fallback for US 1: locate the bright digit
        // component in the shield region and require a narrow/tall "1" shape.
        if let one = detectUSRouteOne(
            image: image,
            roadLine: roadLine
        ) {
            return one
        }

        return nil
    }

    private static func detectUSRouteOne(
        image: UIImage,
        roadLine: OCRLine
    ) -> String? {
        guard let cg = image.cgImage else { return nil }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)
        let b = roadLine.box

        // The shield is directly to the left of a short directional label such
        // as North/South. Keep this narrow to avoid the maneuver arrow/distance.
        let normalizedLeft = max(0, b.minX - 0.115)
        let normalizedRight = max(normalizedLeft, b.minX - 0.010)
        let halfHeight = max(0.030, b.height * 1.10)
        let normalizedBottom = max(0, b.midY - halfHeight)
        let normalizedTop = min(1, b.midY + halfHeight)

        var rect = CGRect(
            x: normalizedLeft * width,
            y: (1 - normalizedTop) * height,
            width: (normalizedRight - normalizedLeft) * width,
            height: (normalizedTop - normalizedBottom) * height
        ).integral
        rect = rect.intersection(
            CGRect(x: 0, y: 0, width: width, height: height)
        )

        guard rect.width > 18,
              rect.height > 18,
              let crop = cg.cropping(to: rect) else { return nil }

        let w = crop.width
        let h = crop.height
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

        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))

        var points: [(x: Int, y: Int)] = []
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Int(bytes[i])
                let g = Int(bytes[i + 1])
                let bl = Int(bytes[i + 2])

                // Apple's shield fill is gray; the numeral itself is close to
                // white. High threshold suppresses most of the shield body.
                if r >= 225, g >= 225, bl >= 225 {
                    points.append((x, y))
                }
            }
        }

        guard !points.isEmpty else { return nil }

        // Connected components among near-white pixels.
        var occupied = [Bool](repeating: false, count: w * h)
        for pt in points {
            occupied[pt.y * w + pt.x] = true
        }
        var visited = [Bool](repeating: false, count: w * h)
        let neighbors = [
            (-1,-1),(0,-1),(1,-1),
            (-1, 0),       (1, 0),
            (-1, 1),(0, 1),(1, 1)
        ]
        var components: [[(x: Int, y: Int)]] = []

        for seed in points {
            let si = seed.y * w + seed.x
            guard !visited[si] else { continue }
            visited[si] = true
            var q = [seed]
            var qi = 0
            var component: [(x: Int, y: Int)] = []

            while qi < q.count {
                let cur = q[qi]
                qi += 1
                component.append(cur)

                for (dx,dy) in neighbors {
                    let nx = cur.x + dx
                    let ny = cur.y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let ni = ny * w + nx
                    guard occupied[ni], !visited[ni] else { continue }
                    visited[ni] = true
                    q.append((nx,ny))
                }
            }

            if component.count >= 8 {
                components.append(component)
            }
        }

        for component in components {
            let xs = component.map(\.x)
            let ys = component.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { continue }

            let cw = maxX - minX + 1
            let ch = maxY - minY + 1
            let centerX = Double(minX + maxX) * 0.5 / Double(max(1, w))

            // A route-number "1" is a narrow, tall bright glyph near the
            // horizontal center of the shield crop. Require strong geometry so
            // this fallback does not invent US 1 from arbitrary street text.
            if ch >= 12,
               Double(ch) / Double(max(1, cw)) >= 1.65,
               cw <= max(18, w / 3),
               centerX >= 0.28,
               centerX <= 0.72 {
                return "1"
            }
        }

        return nil
    }

    private static func extractShortShieldNumber(_ text: String) -> String? {
        guard text.count <= 12 else { return nil }

        let patterns = [
            #"(?:US|U\.?S\.?)?\s*[/\\|{\[(]?\s*(\d{1,3})\s*[}\])]?"#,
            #"[/\\|{\[(]?\s*(\d{1,3})\s*[}\])]?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else { continue }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(
                in: text,
                options: [],
                range: range
            ),
            match.numberOfRanges >= 2,
            let numberRange = Range(match.range(at: 1), in: text)
            else { continue }

            return String(text[numberRange])
        }

        return nil
    }

    private static func upscaleShieldCrop(
        _ image: CGImage,
        scale: Int
    ) -> CGImage? {
        guard scale > 1 else { return image }

        let targetWidth = image.width * scale
        let targetHeight = image.height * scale

        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(
            CGRect(
                x: 0,
                y: 0,
                width: targetWidth,
                height: targetHeight
            )
        )
        ctx.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: targetWidth,
                height: targetHeight
            )
        )

        return ctx.makeImage()
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
    private static let templateSize = 96
    private static let templatePadding = 10

    // These masks are median Apple Maps glyph templates built from the user's
    // supplied screenshots. Offline leave-one-out validation on 11 independent
    // left/right/straight glyph occurrences classified 11/11 correctly.
    private static let leftTemplate = decodeTemplate("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAHAAAAAAAAAAAAAAAHgAAAAAAAAAAAAAAfgAAAAAAAAAAAAAA/wAAAAAAAAAAAAAB/gAAAAAAAAAAAAAH/gAAAAAAAAAAAAAP/AAAAAAAAAAAAAAf/AAAAAAAAAAAAAAf+AAAAAAAAAAAAAB/+AAAAAAAAAAAAAD/8AAAAAAAAAAAAAH/8AAAAAAAAAAAAAP/4AAAAAAAAAAAAA//4AAAAAAAAAAAAB//wAAAAAAAAAAAAD//gAAAAAAAAAAAAD//gAAAAAAAAAAAAP//AAAAAAAAAAAAAf/+AAAAAAAAAAAAA///////gAAAAAAAD////////AAAAAAAH////////4AAAAAAP////////+AAAAAAP/////////AAAAAAf/////////gAAAAAP/////////wAAAAAH/////////8AAAAAD/////////+AAAAAB/////////+AAAAAA//////////AAAAAAf//AAAAf//gAAAAAP//AAAAP//gAAAAAD//gAAAD//gAAAAAB//wAAAA//wAAAAAA//wAAAAf/wAAAAAAf/4AAAAP/4AAAAAAP/4AAAAH/4AAAAAAH/8AAAAD/4AAAAAAD/+AAAAD/4AAAAAAB/+AAAAD/4AAAAAAAf+AAAAB/8AAAAAAAP/AAAAB/8AAAAAAAH/gAAAB/8AAAAAAAD/gAAAB/8AAAAAAAB/wAAAB/8AAAAAAAA/gAAAB/8AAAAAAAAfgAAAB/8AAAAAAAAHgAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAB/8AAAAAAAAAAAAAA/8AAAAAAAAAAAAAA/8AAAAAAAAAAAAAA/4AAAAAAAAAAAAAAf4AAAAAAAAAAAAAAPgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    private static let rightTemplate = decodeTemplate("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA4AAAAAAAAAAAAAAB4AAAAAAAAAAAAAAB+AAAAAAAAAAAAAAD/AAAAAAAAAAAAAAB/gAAAAAAAAAAAAAB/4AAAAAAAAAAAAAA/8AAAAAAAAAAAAAA/+AAAAAAAAAAAAAAf+AAAAAAAAAAAAAAf/gAAAAAAAAAAAAAP/wAAAAAAAAAAAAAP/4AAAAAAAAAAAAAH/8AAAAAAAAAAAAAH//AAAAAAAAAAAAAD//gAAAAAAAAAAAAB//wAAAAAAAAAAAAB//wAAAAAAAAAAAAA//8AAAAAAAAAAAAAf/+AAAAAAAAB///////AAAAAAAA////////wAAAAAAH////////4AAAAAAf////////8AAAAAA/////////8AAAAAB/////////8AAAAAD/////////8AAAAAP/////////4AAAAAf/////////wAAAAAf/////////gAAAAA//////////AAAAAB//+AAAA//+AAAAAB//8AAAB//8AAAAAB//wAAAB//wAAAAAD//AAAAD//gAAAAAD/+AAAAD//AAAAAAH/8AAAAH/+AAAAAAH/4AAAAH/8AAAAAAH/wAAAAP/4AAAAAAH/wAAAAf/wAAAAAAH/wAAAAf/gAAAAAAP/gAAAAf+AAAAAAAP/gAAAA/8AAAAAAAP/gAAAB/4AAAAAAAP/gAAAB/wAAAAAAAP/gAAAD/gAAAAAAAf/gAAAB+AAAAAAAAf/gAAAB+AAAAAAAAf/gAAAB4AAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAf/gAAAAAAAAAAAAAP/AAAAAAAAAAAAAAP/AAAAAAAAAAAAAAH/AAAAAAAAAAAAAAH+AAAAAAAAAAAAAAB8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    private static let straightTemplate = decodeTemplate("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAAAAAAAAAAAABwAAAAAAAAAAAAAAD4AAAAAAAAAAAAAAH8AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAf/AAAAAAAAAAAAAA//gAAAAAAAAAAAAB//wAAAAAAAAAAAAD//4AAAAAAAAAAAAD//4AAAAAAAAAAAAH//8AAAAAAAAAAAAP//+AAAAAAAAAAAAf///AAAAAAAAAAAA////gAAAAAAAAAAB////wAAAAAAAAAAD////4AAAAAAAAAAH////8AAAAAAAAAAP////+AAAAAAAAAAf/////AAAAAAAAAA//////gAAAAAAAAB//////wAAAAAAAAB/+P+P/wAAAAAAAAD/8P+H/4AAAAAAAAH/wP+B/8AAAAAAAAH/AP+Af8AAAAAAAAP8AP+AH8AAAAAAAAH4AP+AD8AAAAAAAADgAP+AA4AAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAP+AAAAAAAAAAAAAAH8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")

    static func classify(image: UIImage, distanceBox: CGRect) -> HudManeuver {
        guard let cg = image.cgImage else { return .straight }

        let width = CGFloat(cg.width)
        let height = CGFloat(cg.height)

        let distanceTop = (1 - distanceBox.maxY) * height
        let distanceBottom = (1 - distanceBox.minY) * height
        let centerY = (distanceTop + distanceBottom) * 0.5
        let cropHeight = max(90, (distanceBottom - distanceTop) * 2.7)
        let cropWidth = min(width * 0.26, max(120, distanceBox.minX * width * 0.95))

        // Keep the dedicated Apple lane-guidance path. It already correctly
        // identifies the highlighted white lane arrow among gray alternatives.
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

        guard rect.width > 20,
              rect.height > 20,
              let crop = cg.cropping(to: rect.integral),
              let data = thresholdedPixels(crop),
              let glyph = dominantArrowComponent(from: data),
              glyph.count > 20 else {
            return .straight
        }

        guard let normalized = normalizeGlyph(glyph) else {
            return .straight
        }

        let scores: [(HudManeuver, Double)] = [
            (.left, bestShiftedIoU(normalized, leftTemplate)),
            (.right, bestShiftedIoU(normalized, rightTemplate)),
            (.straight, bestShiftedIoU(normalized, straightTemplate))
        ].sorted { $0.1 > $1.1 }

        guard let best = scores.first else { return .straight }
        let second = scores.dropFirst().first?.1 ?? 0

        // The supplied screenshots produce ~0.97-1.00 for the correct class
        // and only ~0.19-0.26 for the wrong classes. Keep generous safety
        // thresholds so a distorted/unknown icon does not get confidently
        // converted into the opposite maneuver.
        // Field testing showed some genuine Apple right-turn glyphs land
        // below the original conservative 0.62 threshold even though Right is
        // still clearly the best template. Keep a strict margin, but allow a
        // lower absolute score for Left/Right so a real turn does not collapse
        // to Straight merely because anti-aliasing/crop scale differs.
        let margin = best.1 - second

        if best.0 == .left || best.0 == .right {
            guard best.1 >= 0.38,
                  margin >= 0.075 else {
                return .straight
            }
            return best.0
        }

        guard best.1 >= 0.56,
              margin >= 0.12 else {
            return .straight
        }

        return best.0
    }

    private static func normalizeGlyph(
        _ glyph: [(x: Int, y: Int)]
    ) -> [Bool]? {
        let xs = glyph.map(\.x)
        let ys = glyph.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }

        let sourceWidth = max(1, maxX - minX + 1)
        let sourceHeight = max(1, maxY - minY + 1)
        let usable = templateSize - templatePadding * 2
        let scale = min(
            Double(usable) / Double(sourceWidth),
            Double(usable) / Double(sourceHeight)
        )

        let targetWidth = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let targetHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))
        let offsetX = (templateSize - targetWidth) / 2
        let offsetY = (templateSize - targetHeight) / 2

        var mask = [Bool](repeating: false, count: templateSize * templateSize)

        // Rasterize each source glyph point into the canonical 96x96 mask.
        // Expand one pixel around each projected point to avoid holes from
        // integer scaling/anti-aliasing differences between screenshots.
        for point in glyph {
            let nx = offsetX + Int(
                (Double(point.x - minX) * scale).rounded()
            )
            let ny = offsetY + Int(
                (Double(point.y - minY) * scale).rounded()
            )

            for dy in -1...1 {
                for dx in -1...1 {
                    let x = nx + dx
                    let y = ny + dy
                    guard x >= 0, x < templateSize,
                          y >= 0, y < templateSize else { continue }
                    mask[y * templateSize + x] = true
                }
            }
        }

        return mask
    }

    private static func bestShiftedIoU(
        _ glyph: [Bool],
        _ template: [Bool]
    ) -> Double {
        var best = 0.0

        // Small translation search absorbs sub-pixel/crop alignment variation.
        for dy in -4...4 {
            for dx in -4...4 {
                var intersection = 0
                var union = 0

                for y in 0..<templateSize {
                    for x in 0..<templateSize {
                        let glyphOn = glyph[y * templateSize + x]

                        let tx = x - dx
                        let ty = y - dy
                        let templateOn: Bool
                        if tx >= 0, tx < templateSize,
                           ty >= 0, ty < templateSize {
                            templateOn = template[ty * templateSize + tx]
                        } else {
                            templateOn = false
                        }

                        if glyphOn || templateOn { union += 1 }
                        if glyphOn && templateOn { intersection += 1 }
                    }
                }

                if union > 0 {
                    best = max(best, Double(intersection) / Double(union))
                }
            }
        }

        return best
    }

    private static func decodeTemplate(_ base64: String) -> [Bool] {
        guard let data = Data(base64Encoded: base64) else {
            return [Bool](repeating: false, count: templateSize * templateSize)
        }

        var result = [Bool](repeating: false, count: templateSize * templateSize)
        let bytes = [UInt8](data)

        for index in 0..<result.count {
            let byteIndex = index / 8
            let bitIndex = 7 - (index % 8)
            guard byteIndex < bytes.count else { break }
            result[index] = (bytes[byteIndex] & (1 << bitIndex)) != 0
        }

        return result
    }

    /// Extract connected bright-pixel components and choose the substantial
    /// left-side component most likely to be Apple's maneuver glyph.
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

        let w = maxX - minX + 1
        let h = maxY - minY + 1
        let centerX = Double(minX + maxX) * 0.5

        guard w >= 14, h >= 24 else { return 0 }

        var score = Double(component.count)
        score += Double(h) * 22.0
        score += Double(w) * 5.0

        if centerX > Double(cropWidth) * 0.68 {
            score *= 0.20
        }
        if Double(h) < Double(w) * 0.45 {
            score *= 0.30
        }

        return score
    }

    private static func classifyHighlightedLaneArrow(
        cgImage: CGImage,
        distanceTop: CGFloat,
        distanceHeight: CGFloat
    ) -> HudManeuver? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Lane guidance occupies a horizontal band above the distance/street
        // text and contains several lane arrows distributed across the card.
        // A normal turn card has only ONE maneuver glyph. Previous versions
        // looked at all bright pixels in this band and could therefore mistake
        // a normal single-arrow card for lane guidance, bypassing the template
        // classifier entirely.
        let rect = CGRect(
            x: width * 0.035,
            y: max(0, distanceTop - max(185, distanceHeight * 3.5)),
            width: width * 0.93,
            height: max(120, min(185, distanceHeight * 2.9))
        ).intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard rect.width > 80,
              rect.height > 50,
              let crop = cgImage.cropping(to: rect.integral) else {
            return nil
        }

        // First detect the full set of lane arrows with a deliberately lower
        // luminance threshold so Apple's gray inactive arrows are included.
        guard let grayPixels = thresholdedPixels(crop, minimum: 105),
              grayPixels.points.count > 60 else {
            return nil
        }

        let components = connectedComponents(from: grayPixels)
            .filter { component in
                let xs = component.map(\.x)
                let ys = component.map(\.y)
                guard let minX = xs.min(), let maxX = xs.max(),
                      let minY = ys.min(), let maxY = ys.max() else { return false }

                let w = maxX - minX + 1
                let h = maxY - minY + 1

                // Lane arrows are substantial glyphs. This excludes isolated
                // anti-aliasing/noise and most text fragments.
                return component.count >= 55 &&
                       w >= 16 &&
                       h >= 28 &&
                       h <= grayPixels.height &&
                       Double(h) >= Double(w) * 0.70
            }

        // Require an actual multi-lane pattern. Apple lane guidance examples
        // typically expose 3–4 arrows. Requiring >=3 prevents a normal single
        // turn arrow from ever pre-empting template classification.
        guard components.count >= 3 else {
            return nil
        }

        let centers = components.map { component -> Double in
            let xs = component.map(\.x)
            return Double((xs.min() ?? 0) + (xs.max() ?? 0)) * 0.5
        }.sorted()

        guard let first = centers.first,
              let last = centers.last,
              (last - first) / Double(max(1, grayPixels.width)) >= 0.28 else {
            return nil
        }

        // Now isolate only the bright/white active lane arrow.
        guard let whitePixels = thresholdedPixels(crop, minimum: 205),
              let active = dominantArrowComponent(from: whitePixels),
              active.count >= 20 else {
            return nil
        }

        guard let normalized = normalizeGlyph(active) else {
            return nil
        }

        let scores: [(HudManeuver, Double)] = [
            (.left, bestShiftedIoU(normalized, leftTemplate)),
            (.right, bestShiftedIoU(normalized, rightTemplate)),
            (.straight, bestShiftedIoU(normalized, straightTemplate))
        ].sorted { $0.1 > $1.1 }

        guard let best = scores.first else { return nil }
        let second = scores.dropFirst().first?.1 ?? 0

        guard best.1 >= 0.52,
              best.1 - second >= 0.10 else {
            return nil
        }

        return best.0
    }

    private static func connectedComponents(
        from pixels: PixelSet
    ) -> [[(x: Int, y: Int)]] {
        guard pixels.width > 0, pixels.height > 0 else { return [] }

        let width = pixels.width
        let height = pixels.height
        var occupied = [Bool](repeating: false, count: width * height)

        for point in pixels.points
        where point.x >= 0 && point.x < width &&
              point.y >= 0 && point.y < height {
            occupied[point.y * width + point.x] = true
        }

        var visited = [Bool](repeating: false, count: width * height)
        var output: [[(x: Int, y: Int)]] = []

        let neighbors = [
            (-1, -1), (0, -1), (1, -1),
            (-1,  0),          (1,  0),
            (-1,  1), (0,  1), (1,  1)
        ]

        for seed in pixels.points {
            let index = seed.y * width + seed.x
            guard index >= 0, index < visited.count,
                  !visited[index] else { continue }

            visited[index] = true
            var queue = [seed]
            var cursor = 0
            var component: [(x: Int, y: Int)] = []

            while cursor < queue.count {
                let point = queue[cursor]
                cursor += 1
                component.append(point)

                for (dx, dy) in neighbors {
                    let nx = point.x + dx
                    let ny = point.y + dy
                    guard nx >= 0, nx < width,
                          ny >= 0, ny < height else { continue }

                    let ni = ny * width + nx
                    guard occupied[ni], !visited[ni] else { continue }

                    visited[ni] = true
                    queue.append((x: nx, y: ny))
                }
            }

            if component.count >= 8 {
                output.append(component)
            }
        }

        return output
    }

    private struct PixelSet {
        let width: Int
        let height: Int
        let points: [(x: Int, y: Int)]
    }

    private static func thresholdedPixels(
        _ image: CGImage,
        minimum: Int = 205
    ) -> PixelSet? {
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
                if r > minimum && g > minimum && b > minimum {
                    points.append((x, y))
                }
            }
        }

        return PixelSet(width: w, height: h, points: points)
    }
}
