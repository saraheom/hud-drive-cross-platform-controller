import Foundation

/// One HUD->iPhone protocol body sampled during the v3 OBD speed probe.
/// `time` uses Date.timeIntervalSinceReferenceDate so it can be aligned with
/// independently sampled GPS reference points after the drive.
struct OBDDeepSpeedSample {
    let time: TimeInterval
    let command: Int
    let p1: Int
    let p2: Int
    let payload: Data
}

struct OBDDeepGPSPoint {
    let time: TimeInterval
    let mph: Int
}

struct OBDDeepSpeedCandidate {
    let header: String
    let scalar: String
    let offset: Int
    let lagSeconds: Double
    let samples: Int
    let distinctSpeeds: Int
    let gpsSpanMph: Int
    let rawSpan: Double
    let slopeToMph: Double
    let interceptMph: Double
    let rSquared: Double
    let rmseMph: Double

    var summary: String {
        String(
            format: "%@ %@@%d lag=%+.1fs n=%d distinct=%d gpsSpan=%dmph rawSpan=%.1f slope=%.5f intercept=%+.2f R2=%.4f RMSE=%.2fmph",
            header,
            scalar,
            offset,
            lagSeconds,
            samples,
            distinctSpeeds,
            gpsSpanMph,
            rawSpan,
            slopeToMph,
            interceptMph,
            rSquared,
            rmseMph
        )
    }
}

struct OBDDeepPIDHit {
    let header: String
    let source: String
    let rawKmh: Int
    let gpsMph: Int
    let sampleTime: TimeInterval

    var summary: String {
        String(format: "%@ %@ raw=%dkm/h gps=%dmph t=%.3f", header, source, rawKmh, gpsMph, sampleTime)
    }
}

/// Offline/statistical analyzer used by the v3 road probe.
///
/// Unlike v2, this does not require a candidate byte to already look like mph
/// or km/h. It evaluates changing scalar fields with linear regression against
/// GPS across several temporal lags. This catches mph, km/h, deci-units,
/// scaled counters, and a modest fixed offset while rejecting constants such as
/// the previously observed `... 00 00 00 06` status value.
enum OBDDeepSpeedAnalyzer {
    private struct CandidateKey: Hashable {
        let header: String
        let scalar: String
        let offset: Int
        let lagTenths: Int
    }

    private struct RegressionAccumulator {
        var n = 0
        var sumX = 0.0
        var sumY = 0.0
        var sumXX = 0.0
        var sumYY = 0.0
        var sumXY = 0.0
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var distinctRoundedY = Set<Int>()

        mutating func add(x: Double, y: Double) {
            guard x.isFinite, y.isFinite else { return }
            n += 1
            sumX += x
            sumY += y
            sumXX += x * x
            sumYY += y * y
            sumXY += x * y
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
            distinctRoundedY.insert(Int(y.rounded()))
        }

        func candidate(for key: CandidateKey) -> OBDDeepSpeedCandidate? {
            guard n >= 8 else { return nil }
            let dn = Double(n)
            let centeredXX = sumXX - (sumX * sumX / dn)
            let centeredYY = sumYY - (sumY * sumY / dn)
            let centeredXY = sumXY - (sumX * sumY / dn)
            guard centeredXX > 0.0001, centeredYY > 0.0001 else { return nil }

            let slope = centeredXY / centeredXX
            let intercept = (sumY - slope * sumX) / dn
            guard slope > 0, slope.isFinite, intercept.isFinite else { return nil }

            let r2 = max(0.0, min(1.0, (centeredXY * centeredXY) / (centeredXX * centeredYY)))
            let sse = max(0.0, centeredYY - slope * centeredXY)
            let rmse = sqrt(sse / dn)
            let gpsSpan = Int((maxY - minY).rounded())
            let rawSpan = maxX - minX

            // Require actual road-test variation. This intentionally rejects
            // the fixed `6` status field that fooled the early exact-match probe.
            guard distinctRoundedY.count >= 4, gpsSpan >= 8, rawSpan > 0 else { return nil }

            return OBDDeepSpeedCandidate(
                header: key.header,
                scalar: key.scalar,
                offset: key.offset,
                lagSeconds: Double(key.lagTenths) / 10.0,
                samples: n,
                distinctSpeeds: distinctRoundedY.count,
                gpsSpanMph: gpsSpan,
                rawSpan: rawSpan,
                slopeToMph: slope,
                interceptMph: intercept,
                rSquared: r2,
                rmseMph: rmse
            )
        }
    }

    private static let lagTenths = [-20, -10, -5, 0, 5, 10, 20]

    static func analyze(samples: [OBDDeepSpeedSample], gps: [OBDDeepGPSPoint]) -> [OBDDeepSpeedCandidate] {
        guard !samples.isEmpty, gps.count >= 4 else { return [] }
        let gpsSorted = gps.sorted { $0.time < $1.time }
        var accumulators: [CandidateKey: RegressionAccumulator] = [:]

        for sample in samples {
            let bytes = [UInt8](sample.payload)
            guard !bytes.isEmpty else { continue }
            let header = "hdr=\(sample.command)/\(sample.p1)/\(sample.p2)"

            for lag in lagTenths {
                let targetTime = sample.time + Double(lag) / 10.0
                guard let reference = nearestGPS(to: targetTime, gps: gpsSorted), reference.mph >= 3 else { continue }
                let y = Double(reference.mph)

                func add(_ scalar: String, _ offset: Int, _ x: Double) {
                    // Vehicle speed is unlikely to need a raw value outside this
                    // broad range; bounding it keeps unrelated timestamps/counters
                    // from dominating the regression search.
                    guard x.isFinite, x >= 0, x <= 20_000 else { return }
                    let key = CandidateKey(header: header, scalar: scalar, offset: offset, lagTenths: lag)
                    var acc = accumulators[key] ?? RegressionAccumulator()
                    acc.add(x: x, y: y)
                    accumulators[key] = acc
                }

                for i in bytes.indices {
                    add("u8", i, Double(bytes[i]))
                    let hi = Int(bytes[i] >> 4)
                    let lo = Int(bytes[i] & 0x0F)
                    if hi <= 9, lo <= 9 {
                        add("bcd8", i, Double(hi * 10 + lo))
                    }
                }

                if bytes.count >= 2 {
                    for i in 0..<(bytes.count - 1) {
                        let be = (UInt16(bytes[i]) << 8) | UInt16(bytes[i + 1])
                        let le = (UInt16(bytes[i + 1]) << 8) | UInt16(bytes[i])
                        add("u16be", i, Double(be))
                        add("u16le", i, Double(le))
                    }
                }

                if bytes.count >= 4 {
                    for i in 0...(bytes.count - 4) {
                        let be = (UInt32(bytes[i]) << 24) |
                            (UInt32(bytes[i + 1]) << 16) |
                            (UInt32(bytes[i + 2]) << 8) |
                            UInt32(bytes[i + 3])
                        let le = (UInt32(bytes[i + 3]) << 24) |
                            (UInt32(bytes[i + 2]) << 16) |
                            (UInt32(bytes[i + 1]) << 8) |
                            UInt32(bytes[i])
                        add("u32be", i, Double(be))
                        add("u32le", i, Double(le))
                    }
                }
            }
        }

        return accumulators.compactMap { key, acc in acc.candidate(for: key) }
            .filter { candidate in
                // Keep the report focused. A lower-quality candidate remains in
                // the raw report's frame-key section, but only strong correlations
                // are promoted as possible speed fields.
                candidate.rSquared >= 0.80 && candidate.rmseMph <= 8.0
            }
            .sorted {
                if abs($0.rSquared - $1.rSquared) > 0.0001 { return $0.rSquared > $1.rSquared }
                if abs($0.rmseMph - $1.rmseMph) > 0.01 { return $0.rmseMph < $1.rmseMph }
                if $0.distinctSpeeds != $1.distinctSpeeds { return $0.distinctSpeeds > $1.distinctSpeeds }
                return $0.samples > $1.samples
            }
    }

    static func directPIDHits(samples: [OBDDeepSpeedSample], gps: [OBDDeepGPSPoint]) -> [OBDDeepPIDHit] {
        guard !samples.isEmpty else { return [] }
        let gpsSorted = gps.sorted { $0.time < $1.time }
        var hits: [OBDDeepPIDHit] = []

        for sample in samples {
            let bytes = [UInt8](sample.payload)
            let header = "hdr=\(sample.command)/\(sample.p1)/\(sample.p2)"
            let gpsMph = nearestGPS(to: sample.time, gps: gpsSorted)?.mph ?? 0

            if bytes.count >= 3 {
                for i in 0...(bytes.count - 3) where bytes[i] == 0x41 && bytes[i + 1] == 0x0D {
                    hits.append(OBDDeepPIDHit(
                        header: header,
                        source: "binary-410D@\(i)",
                        rawKmh: Int(bytes[i + 2]),
                        gpsMph: gpsMph,
                        sampleTime: sample.time
                    ))
                }
            }

            if let ascii = String(data: sample.payload, encoding: .ascii) {
                let upper = ascii.uppercased()
                let compact = upper.filter { $0.isHexDigit }
                var searchStart = compact.startIndex
                while let range = compact.range(of: "410D", range: searchStart..<compact.endIndex) {
                    let valueStart = range.upperBound
                    guard let valueEnd = compact.index(valueStart, offsetBy: 2, limitedBy: compact.endIndex), valueEnd <= compact.endIndex else { break }
                    let hex = String(compact[valueStart..<valueEnd])
                    if hex.count == 2, let kmh = Int(hex, radix: 16) {
                        hits.append(OBDDeepPIDHit(
                            header: header,
                            source: "ascii-410D",
                            rawKmh: kmh,
                            gpsMph: gpsMph,
                            sampleTime: sample.time
                        ))
                    }
                    searchStart = valueEnd
                    if searchStart >= compact.endIndex { break }
                }
            }
        }
        return hits
    }

    static func frameKeySummary(samples: [OBDDeepSpeedSample]) -> [String] {
        var counts: [String: Int] = [:]
        var distinctPayloads: [String: Set<Data>] = [:]
        for sample in samples {
            let key = "\(sample.command)/\(sample.p1)/\(sample.p2)"
            counts[key, default: 0] += 1
            if distinctPayloads[key, default: []].count < 256 {
                distinctPayloads[key, default: []].insert(sample.payload)
            }
        }
        return counts.keys.sorted().map { key in
            "hdr=\(key) frames=\(counts[key] ?? 0) distinctPayloads=\(distinctPayloads[key]?.count ?? 0)"
        }
    }

    static func report(
        label: String,
        reason: String,
        samples: [OBDDeepSpeedSample],
        gps: [OBDDeepGPSPoint],
        candidates: [OBDDeepSpeedCandidate],
        pidHits: [OBDDeepPIDHit]
    ) -> String {
        let speeds = gps.map(\.mph)
        let gpsMin = speeds.min() ?? 0
        let gpsMax = speeds.max() ?? 0
        var lines: [String] = []
        lines.append("HUD OBD Speed Probe v3")
        lines.append("label=\(label)")
        lines.append("reason=\(reason)")
        lines.append("frames=\(samples.count)")
        lines.append("gpsSamples=\(gps.count) gpsRange=\(gpsMin)-\(gpsMax)mph")
        lines.append("directPID410DHits=\(pidHits.count)")
        lines.append("")
        lines.append("TOP REGRESSION CANDIDATES")
        if candidates.isEmpty {
            lines.append("none")
        } else {
            for (index, candidate) in candidates.prefix(25).enumerated() {
                lines.append("\(index + 1). \(candidate.summary)")
            }
        }
        lines.append("")
        lines.append("DIRECT 41 0D / ASCII 410D HITS")
        if pidHits.isEmpty {
            lines.append("none")
        } else {
            for hit in pidHits.prefix(100) { lines.append(hit.summary) }
        }
        lines.append("")
        lines.append("FRAME KEYS")
        lines.append(contentsOf: frameKeySummary(samples: samples))
        lines.append("")
        lines.append("RAW SAMPLES (bounded payloads)")
        let gpsSorted = gps.sorted { $0.time < $1.time }
        for sample in samples.prefix(12_000) {
            let gpsMph = nearestGPS(to: sample.time, gps: gpsSorted)?.mph ?? 0
            lines.append(
                String(format: "t=%.3f hdr=%d/%d/%d gps=%dmph payload=%@",
                       sample.time,
                       sample.command,
                       sample.p1,
                       sample.p2,
                       gpsMph,
                       hex(sample.payload))
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func nearestGPS(to time: TimeInterval, gps: [OBDDeepGPSPoint]) -> OBDDeepGPSPoint? {
        guard !gps.isEmpty else { return nil }
        var low = 0
        var high = gps.count
        while low < high {
            let mid = (low + high) / 2
            if gps[mid].time < time { low = mid + 1 } else { high = mid }
        }
        if low == 0 { return gps[0] }
        if low >= gps.count { return gps[gps.count - 1] }
        let before = gps[low - 1]
        let after = gps[low]
        return abs(before.time - time) <= abs(after.time - time) ? before : after
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
