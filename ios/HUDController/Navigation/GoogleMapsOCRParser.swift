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
            return GoogleMapsOCRParser.parseGoogle(lines: cleaned, rawText: rawText)
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
        parseGoogle(lines: lines, rawText: rawText)
    }

    fileprivate static func parseGoogle(
        lines: [String],
        rawText: String
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

        var selectedDistance = 0
        var originalDistance = ""
        var instructionLine = ""
        var distanceLine = ""
        var bestIndex = Int.max

        // Favor the top/current instruction. Never choose a later upcoming
        // maneuver simply because OCR reordered a few words.
        for (i, line) in cleaned.enumerated() {
            guard let meters = ExternalNavigationOCRParser.parseDistanceMeters(line),
                  isNavigationDistanceLine(line) else { continue }

            let upper = min(cleaned.count - 1, i + 3)
            guard i < upper else { continue }

            for j in (i + 1)...upper where ExternalNavigationOCRParser.isExplicitGoogleManeuver(cleaned[j]) {
                if i < bestIndex {
                    bestIndex = i
                    selectedDistance = meters
                    originalDistance = line
                    distanceLine = line
                    instructionLine = cleaned[j]
                }
                break
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
                        distanceLine = cleaned[j]
                        instructionLine = line
                        break
                    }
                }
                if !instructionLine.isEmpty { break }
            }
        }

        let maneuver = ExternalNavigationOCRParser.maneuverFromText(instructionLine)
        let street = streetFromInstruction(instructionLine)
        let primary = primaryInstruction(instructionLine, maneuver: maneuver)

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

    private static func primaryInstruction(_ text: String, maneuver: HudManeuver) -> String {
        if let range = text.lowercased().range(of: " onto ") {
            return String(text[..<range.lowerBound])
        }
        return text.isEmpty ? maneuver.label : text
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
        if index + 1 < lines.count {
            for j in (index + 1)..<min(lines.count, index + 4) {
                let candidate = lines[j]
                let l = candidate.lowercased()
                if l.contains("end route") ||
                    ExternalNavigationOCRParser.isStandaloneDistance(candidate) {
                    break
                }
                if !candidate.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
                    road = stripRouteShieldOCR(candidate)
                    if !road.isEmpty { break }
                }
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

        var left = 0
        var right = 0
        var top = 0

        for point in data.points {
            if point.x < w / 3 { left += 1 }
            if point.x > (w * 2) / 3 { right += 1 }
            if point.y < h / 3 { top += 1 }
        }

        let total = max(1, data.points.count)
        let leftRatio = Double(left) / Double(total)
        let rightRatio = Double(right) / Double(total)
        let topRatio = Double(top) / Double(total)

        if rightRatio > leftRatio * 1.20 && rightRatio > 0.23 { return .right }
        if leftRatio > rightRatio * 1.20 && leftRatio > 0.23 { return .left }
        if topRatio > 0.30 { return .straight }

        return .straight
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
