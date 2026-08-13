import Foundation
import Vision
import UIKit

struct ParsedExternalNavigation: Equatable {
    var instruction: NavigationInstruction
    var rawText: String
    var isValidNavigation: Bool
    var confidence: Int
    var validationReason: String
}

enum GoogleMapsOCRParser {
    static func recognize(_ image: UIImage) async throws -> ParsedExternalNavigation {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "HUDOCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Image has no CGImage"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let raw = lines.joined(separator: "\n")
                continuation.resume(returning: parse(lines: lines, rawText: raw))
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

    static func parse(lines: [String], rawText: String) -> ParsedExternalNavigation {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Google Maps' CarPlay companion screen normally exposes a distance
        // line ("In 300 ft", "0.7 miles") followed closely by a maneuver line.
        // Do not accept arbitrary numeric text elsewhere on the screen.
        var selectedDistance = 0
        var instructionLine = ""
        var distanceLine = ""
        var pairDistance = Int.max

        for (i, line) in cleaned.enumerated() {
            guard let meters = parseDistanceMeters(line),
                  isNavigationDistanceLine(line) else { continue }

            let upper = min(cleaned.count - 1, i + 3)
            if i < upper {
                for j in (i + 1)...upper {
                    if isExplicitManeuverLine(cleaned[j]) {
                        let gap = j - i
                        if gap < pairDistance {
                            pairDistance = gap
                            selectedDistance = meters
                            distanceLine = line
                            instructionLine = cleaned[j]
                        }
                    }
                }
            }
        }

        // Fallback for layouts where instruction precedes distance by one row.
        if instructionLine.isEmpty {
            for (i, line) in cleaned.enumerated() where isExplicitManeuverLine(line) {
                let lower = max(0, i - 2)
                if lower < i {
                    for j in lower..<i {
                        if let meters = parseDistanceMeters(cleaned[j]),
                           isNavigationDistanceLine(cleaned[j]) {
                            selectedDistance = meters
                            distanceLine = cleaned[j]
                            instructionLine = line
                            break
                        }
                    }
                }
                if !instructionLine.isEmpty { break }
            }
        }

        let maneuver = maneuverFromText(instructionLine)
        let street = streetFromInstruction(instructionLine)
        let primary = primaryInstruction(instructionLine, maneuver: maneuver)

        var confidence = 0
        var reasons: [String] = []

        if !instructionLine.isEmpty {
            confidence += 45
            reasons.append("explicit maneuver")
        }
        if selectedDistance > 0 {
            confidence += 35
            reasons.append("paired distance")
        }
        if !street.isEmpty {
            confidence += 15
            reasons.append("street/road")
        }
        if distanceLine.lowercased().contains("in ") ||
            distanceLine.lowercased().contains("then ") {
            confidence += 5
            reasons.append("navigation distance wording")
        }

        // Reject obvious HUD Controller UI text even if OCR happened to find a
        // distance elsewhere in the frame.
        let rejectedUIWords = [
            "screen capture", "keep screen", "automatically send",
            "saved screenshot", "frames ocr", "brightness", "spotify",
            "reconnect", "widget", "notification", "bluetooth"
        ]
        let loweredInstruction = instructionLine.lowercased()
        let containsOwnUI = rejectedUIWords.contains(where: loweredInstruction.contains)
        if containsOwnUI {
            confidence = 0
            reasons = ["HUD Controller UI text"]
        }

        let valid = confidence >= 80 &&
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
            validationReason: reasons.joined(separator: ", ")
        )
    }

    private static func parseDistanceMeters(_ text: String) -> Int? {
        let s = text.lowercased()
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(ft|feet|mi|mile|miles)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let match = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let numberRange = Range(match.range(at: 1), in: s),
              let unitRange = Range(match.range(at: 2), in: s),
              let value = Double(s[numberRange]) else { return nil }
        let unit = String(s[unitRange])
        if unit == "ft" || unit == "feet" { return Int((value / 3.28084).rounded()) }
        return Int((value * 1609.344).rounded())
    }

    private static func isExplicitManeuverLine(_ text: String) -> Bool {
        let s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "turn left", "turn right",
            "keep left", "keep right",
            "take the", "take exit", "take a",
            "continue", "merge",
            "make a u-turn", "make a u turn", "u-turn", "uturn",
            "exit left", "exit right",
            "slight left", "slight right",
            "sharp left", "sharp right",
            "enter the roundabout", "at the roundabout"
        ]
        return prefixes.contains(where: s.hasPrefix)
    }

    private static func isNavigationDistanceLine(_ text: String) -> Bool {
        let s = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard parseDistanceMeters(s) != nil else { return false }

        // Accept the common active-step forms and simple standalone map
        // distances, but reject arbitrary measurements embedded in app UI.
        if s.hasPrefix("in ") || s.hasPrefix("then ") { return true }

        let pattern = #"^[0-9]+(?:\.[0-9]+)?\s*(ft|feet|mi|mile|miles)$"#
        return (try? NSRegularExpression(pattern: pattern))?
            .firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func maneuverFromText(_ text: String) -> HudManeuver {
        let s = text.lowercased()
        if s.contains("u-turn") || s.contains("uturn") { return .uTurn }
        if s.contains("keep left") { return .keepLeft }
        if s.contains("keep right") { return .keepRight }
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

    private static func streetFromInstruction(_ text: String) -> String {
        let lower = text.lowercased()
        for marker in [" onto ", " toward ", " towards ", " to stay on ", " to "] {
            if let range = lower.range(of: marker) {
                return String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
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
