import Foundation
import Vision
import UIKit

struct ParsedExternalNavigation: Equatable {
    var instruction: NavigationInstruction
    var rawText: String
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
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        var distanceMeters = 0
        var distanceIndex: Int?
        for (i, line) in cleaned.enumerated() {
            if let value = parseDistanceMeters(line) {
                distanceMeters = value
                distanceIndex = i
                break
            }
        }

        let instructionLine: String = {
            if let i = distanceIndex {
                for j in (i + 1)..<min(cleaned.count, i + 4) {
                    if looksLikeManeuver(cleaned[j]) { return cleaned[j] }
                }
            }
            return cleaned.first(where: looksLikeManeuver) ?? cleaned.first ?? ""
        }()

        let maneuver = maneuverFromText(instructionLine)
        let street = streetFromInstruction(instructionLine)
        let primary = primaryInstruction(instructionLine, maneuver: maneuver)

        return ParsedExternalNavigation(
            instruction: NavigationInstruction(
                maneuver: maneuver,
                distanceMeters: distanceMeters,
                primaryText: primary,
                streetName: street
            ),
            rawText: rawText
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

    private static func looksLikeManeuver(_ text: String) -> Bool {
        let s = text.lowercased()
        return ["turn ", "keep ", "take ", "continue", "merge", "u-turn", "uturn", "exit", "ramp", "roundabout"]
            .contains(where: s.contains)
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
