import Foundation

/// Lightweight, iPhone-side H.264 validator for the raw v8.17 MainVideo stream.
///
/// Field captures show that the U2W v8.11 exporter can mirror genuine 800×480
/// CarPlay H.264 and unrelated bytes through the same captured transport. The
/// adapter should therefore stay computationally simple: v8.17 forwards bytes,
/// while this validator rejects false Annex-B markers before VideoToolbox sees
/// them. No U2W/AppleCarPlay process is modified by this code.
struct H264MainVideoSanitizerStats: Equatable {
    var rawNALs = 0
    var acceptedNALs = 0
    var rejectedNALs = 0
    var acceptedSPS = 0
    var acceptedPPS = 0
    var acceptedIDR = 0
    var acceptedSlices = 0
    var lastAcceptedAt: Date?

    var summary: String {
        "raw \(rawNALs) • valid \(acceptedNALs) • rejected \(rejectedNALs) • " +
        "SPS \(acceptedSPS) PPS \(acceptedPPS) IDR \(acceptedIDR) slices \(acceptedSlices)"
    }
}

enum H264MainVideoNALKind: String {
    case sps = "SPS"
    case pps = "PPS"
    case idr = "IDR"
    case slice = "slice"
}

struct H264SanitizedNAL {
    let data: Data
    let kind: H264MainVideoNALKind
}

final class H264MainVideoSanitizer {
    private struct SPSInfo {
        let id: UInt32
        let width: Int
        let height: Int
        let log2MaxFrameNumMinus4: UInt32
        let picOrderCntType: UInt32
        let log2MaxPicOrderCntLSBMinus4: UInt32
        let frameMbsOnlyFlag: Bool
        let deltaPicOrderAlwaysZeroFlag: Bool
    }

    private struct PPSInfo {
        let id: UInt32
        let spsID: UInt32
        let bottomFieldPicOrderInFramePresentFlag: Bool
    }

    private struct SliceInfo {
        let firstMacroblock: UInt32
        let ppsID: UInt32
        let frameNum: UInt32
        let nalType: UInt8
        let idrPicID: UInt32?
    }

    private struct SliceFrameKey: Equatable {
        let ppsID: UInt32
        let frameNum: UInt32
        let nalType: UInt8
        let idrPicID: UInt32?
    }

    private struct BitReader {
        let bytes: [UInt8]
        private(set) var bitIndex = 0
        private(set) var failed = false

        mutating func bit() -> UInt32 {
            guard bitIndex < bytes.count * 8 else {
                failed = true
                return 0
            }
            let byte = bytes[bitIndex / 8]
            let shift = 7 - (bitIndex % 8)
            bitIndex += 1
            return UInt32((byte >> shift) & 1)
        }

        mutating func bits(_ count: Int) -> UInt32 {
            guard (0...24).contains(count) else {
                failed = true
                return 0
            }
            var value: UInt32 = 0
            for _ in 0..<count {
                value = (value << 1) | bit()
            }
            return value
        }

        mutating func unsignedExpGolomb() -> UInt32 {
            var leadingZeroBits = 0
            while !failed {
                if bit() == 1 { break }
                leadingZeroBits += 1
                if leadingZeroBits > 24 {
                    failed = true
                    return 0
                }
            }
            guard !failed else { return 0 }
            if leadingZeroBits == 0 { return 0 }
            return ((UInt32(1) << UInt32(leadingZeroBits)) - 1) + bits(leadingZeroBits)
        }

        mutating func signedExpGolomb() -> Int32 {
            let code = unsignedExpGolomb()
            if code & 1 == 1 {
                return Int32((code + 1) >> 1)
            }
            return -Int32(code >> 1)
        }
    }

    private let expectedWidth: Int
    private let expectedHeight: Int
    private var spsByID: [UInt32: SPSInfo] = [:]
    private var ppsByID: [UInt32: PPSInfo] = [:]
    private var continuationFrame: SliceFrameKey?
    private(set) var stats = H264MainVideoSanitizerStats()

    init(expectedWidth: Int = 800, expectedHeight: Int = 480) {
        self.expectedWidth = expectedWidth
        self.expectedHeight = expectedHeight
    }

    func reset(clearParameterSets: Bool = true) {
        stats = H264MainVideoSanitizerStats()
        continuationFrame = nil
        if clearParameterSets {
            spsByID.removeAll(keepingCapacity: true)
            ppsByID.removeAll(keepingCapacity: true)
        }
    }

    /// Preserve the last validated parameter-set relationship across a transport
    /// reconnect. v8.17 can restart a client in the middle of a contaminated
    /// segment; retaining known-good SPS/PPS lets a later genuine slice recover
    /// without forcing another adapter-side scan.
    func prepareForTransportReconnect() {
        continuationFrame = nil
    }

    func process(_ nal: Data) -> H264SanitizedNAL? {
        stats.rawNALs += 1
        guard let first = nal.first,
              first & 0x80 == 0 else {
            reject()
            return nil
        }

        let type = first & 0x1F
        switch type {
        case 7:
            guard let info = parseSPS(nal),
                  info.width == expectedWidth,
                  info.height == expectedHeight else {
                reject()
                return nil
            }
            spsByID[info.id] = info
            // A changed/repeated SPS must be followed by a PPS again before VCL
            // data is admitted. This prevents stale PPS state from legitimizing
            // random bytes after a generation rollover.
            ppsByID = ppsByID.filter { $0.value.spsID != info.id }
            continuationFrame = nil
            accept(kind: .sps)
            stats.acceptedSPS += 1
            return H264SanitizedNAL(data: nal, kind: .sps)

        case 8:
            guard let info = parsePPS(nal) else {
                reject()
                return nil
            }
            ppsByID[info.id] = info
            continuationFrame = nil
            accept(kind: .pps)
            stats.acceptedPPS += 1
            return H264SanitizedNAL(data: nal, kind: .pps)

        case 1, 5:
            guard let info = parseSlice(nal) else {
                reject()
                return nil
            }

            let key = SliceFrameKey(
                ppsID: info.ppsID,
                frameNum: info.frameNum,
                nalType: info.nalType,
                idrPicID: info.idrPicID
            )
            if info.firstMacroblock == 0 {
                continuationFrame = key
            } else {
                // Multi-slice pictures are allowed only when the continuation
                // immediately belongs to an already-validated first slice.
                guard continuationFrame == key else {
                    reject()
                    return nil
                }
            }

            let kind: H264MainVideoNALKind = type == 5 ? .idr : .slice
            accept(kind: kind)
            stats.acceptedSlices += 1
            if type == 5 { stats.acceptedIDR += 1 }
            return H264SanitizedNAL(data: nal, kind: kind)

        default:
            // AUD/SEI and every unknown type are intentionally dropped. The map
            // decoder needs only SPS/PPS/VCL, and accepting fewer classes sharply
            // reduces the chance that unrelated CarPlay transport bytes reach VT.
            reject()
            return nil
        }
    }

    private func accept(kind: H264MainVideoNALKind) {
        stats.acceptedNALs += 1
        stats.lastAcceptedAt = Date()
    }

    private func reject() {
        stats.rejectedNALs += 1
    }

    private func parseSPS(_ nal: Data) -> SPSInfo? {
        guard nal.count >= 5,
              nal.count <= 256,
              let first = nal.first,
              first & 0x80 == 0,
              first & 0x1F == 7 else { return nil }

        var reader = BitReader(bytes: Self.rbsp(from: nal.dropFirst(), limit: 512))
        let profileIDC = reader.bits(8)
        _ = reader.bits(8) // constraint flags + reserved_zero_2bits
        let levelIDC = reader.bits(8)
        let spsID = reader.unsignedExpGolomb()
        guard !reader.failed, spsID <= 31, levelIDC > 0, levelIDC <= 60 else { return nil }

        var chromaFormatIDC: UInt32 = 1
        var separateColourPlane = false
        let highProfiles: Set<UInt32> = [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135]
        if highProfiles.contains(profileIDC) {
            chromaFormatIDC = reader.unsignedExpGolomb()
            guard chromaFormatIDC <= 3 else { return nil }
            if chromaFormatIDC == 3 {
                separateColourPlane = reader.bit() == 1
            }
            guard reader.unsignedExpGolomb() <= 6,
                  reader.unsignedExpGolomb() <= 6 else { return nil }
            _ = reader.bit() // qpprime_y_zero_transform_bypass_flag
            if reader.bit() == 1 {
                let count = chromaFormatIDC == 3 ? 12 : 8
                for index in 0..<count where reader.bit() == 1 {
                    guard Self.skipScalingList(&reader, size: index < 6 ? 16 : 64) else { return nil }
                }
            }
        }

        let log2MaxFrameNumMinus4 = reader.unsignedExpGolomb()
        guard log2MaxFrameNumMinus4 <= 12 else { return nil }
        let picOrderCntType = reader.unsignedExpGolomb()
        guard picOrderCntType <= 2 else { return nil }

        var log2MaxPicOrderCntLSBMinus4: UInt32 = 0
        var deltaPicOrderAlwaysZeroFlag = false
        if picOrderCntType == 0 {
            log2MaxPicOrderCntLSBMinus4 = reader.unsignedExpGolomb()
            guard log2MaxPicOrderCntLSBMinus4 <= 12 else { return nil }
        } else if picOrderCntType == 1 {
            deltaPicOrderAlwaysZeroFlag = reader.bit() == 1
            _ = reader.signedExpGolomb()
            _ = reader.signedExpGolomb()
            let cycleCount = reader.unsignedExpGolomb()
            guard cycleCount <= 16 else { return nil }
            for _ in 0..<cycleCount { _ = reader.signedExpGolomb() }
        }

        guard reader.unsignedExpGolomb() <= 16 else { return nil } // max_num_ref_frames
        _ = reader.bit() // gaps_in_frame_num_value_allowed_flag
        let widthInMacroblocksMinus1 = reader.unsignedExpGolomb()
        let heightInMapUnitsMinus1 = reader.unsignedExpGolomb()
        guard widthInMacroblocksMinus1 <= 255,
              heightInMapUnitsMinus1 <= 255 else { return nil }

        let frameMbsOnlyFlag = reader.bit() == 1
        if !frameMbsOnlyFlag { _ = reader.bit() }
        _ = reader.bit() // direct_8x8_inference_flag

        var cropLeft: UInt32 = 0
        var cropRight: UInt32 = 0
        var cropTop: UInt32 = 0
        var cropBottom: UInt32 = 0
        if reader.bit() == 1 {
            cropLeft = reader.unsignedExpGolomb()
            cropRight = reader.unsignedExpGolomb()
            cropTop = reader.unsignedExpGolomb()
            cropBottom = reader.unsignedExpGolomb()
            guard max(cropLeft, cropRight, cropTop, cropBottom) <= 255 else { return nil }
        }
        guard !reader.failed else { return nil }

        var width = Int(widthInMacroblocksMinus1 + 1) * 16
        var height = Int(2 - (frameMbsOnlyFlag ? 1 : 0)) * Int(heightInMapUnitsMinus1 + 1) * 16

        let cropUnitX: Int
        let cropUnitY: Int
        if chromaFormatIDC == 0 || separateColourPlane {
            cropUnitX = 1
            cropUnitY = frameMbsOnlyFlag ? 1 : 2
        } else if chromaFormatIDC == 1 {
            cropUnitX = 2
            cropUnitY = 2 * (frameMbsOnlyFlag ? 1 : 2)
        } else if chromaFormatIDC == 2 {
            cropUnitX = 2
            cropUnitY = frameMbsOnlyFlag ? 1 : 2
        } else {
            cropUnitX = 1
            cropUnitY = frameMbsOnlyFlag ? 1 : 2
        }

        let horizontalCrop = Int(cropLeft + cropRight) * cropUnitX
        let verticalCrop = Int(cropTop + cropBottom) * cropUnitY
        guard horizontalCrop < width, verticalCrop < height else { return nil }
        width -= horizontalCrop
        height -= verticalCrop

        return SPSInfo(
            id: spsID,
            width: width,
            height: height,
            log2MaxFrameNumMinus4: log2MaxFrameNumMinus4,
            picOrderCntType: picOrderCntType,
            log2MaxPicOrderCntLSBMinus4: log2MaxPicOrderCntLSBMinus4,
            frameMbsOnlyFlag: frameMbsOnlyFlag,
            deltaPicOrderAlwaysZeroFlag: deltaPicOrderAlwaysZeroFlag
        )
    }

    private func parsePPS(_ nal: Data) -> PPSInfo? {
        guard nal.count >= 2,
              nal.count <= 256,
              let first = nal.first,
              first & 0x80 == 0,
              first & 0x1F == 8 else { return nil }

        var reader = BitReader(bytes: Self.rbsp(from: nal.dropFirst(), limit: 512))
        let ppsID = reader.unsignedExpGolomb()
        let spsID = reader.unsignedExpGolomb()
        guard !reader.failed,
              ppsID <= 255,
              spsByID[spsID] != nil else { return nil }

        _ = reader.bit() // entropy_coding_mode_flag
        let bottomField = reader.bit() == 1
        let numSliceGroupsMinus1 = reader.unsignedExpGolomb()
        guard !reader.failed, numSliceGroupsMinus1 == 0 else { return nil }

        return PPSInfo(
            id: ppsID,
            spsID: spsID,
            bottomFieldPicOrderInFramePresentFlag: bottomField
        )
    }

    private func parseSlice(_ nal: Data) -> SliceInfo? {
        guard nal.count >= 4,
              nal.count <= 512 * 1024,
              let first = nal.first,
              first & 0x80 == 0 else { return nil }
        let nalType = first & 0x1F
        guard nalType == 1 || nalType == 5 else { return nil }

        var reader = BitReader(bytes: Self.rbsp(from: nal.dropFirst(), limit: 512))
        let firstMacroblock = reader.unsignedExpGolomb()
        let sliceType = reader.unsignedExpGolomb()
        let ppsID = reader.unsignedExpGolomb()
        guard !reader.failed,
              sliceType <= 9,
              let pps = ppsByID[ppsID],
              let sps = spsByID[pps.spsID] else { return nil }

        let maxMacroblocks = UInt32(((sps.width + 15) / 16) * ((sps.height + 15) / 16))
        guard firstMacroblock < maxMacroblocks else { return nil }

        let frameNumBits = Int(sps.log2MaxFrameNumMinus4 + 4)
        guard (4...16).contains(frameNumBits) else { return nil }
        let frameNum = reader.bits(frameNumBits)

        var fieldPicture = false
        if !sps.frameMbsOnlyFlag {
            fieldPicture = reader.bit() == 1
            if fieldPicture { _ = reader.bit() }
        }

        var idrPicID: UInt32?
        if nalType == 5 {
            let value = reader.unsignedExpGolomb()
            guard value <= 65_535 else { return nil }
            idrPicID = value
        }

        if sps.picOrderCntType == 0 {
            let bits = Int(sps.log2MaxPicOrderCntLSBMinus4 + 4)
            guard (4...16).contains(bits) else { return nil }
            _ = reader.bits(bits)
            if pps.bottomFieldPicOrderInFramePresentFlag && !fieldPicture {
                _ = reader.signedExpGolomb()
            }
        } else if sps.picOrderCntType == 1 && !sps.deltaPicOrderAlwaysZeroFlag {
            _ = reader.signedExpGolomb()
            if pps.bottomFieldPicOrderInFramePresentFlag && !fieldPicture {
                _ = reader.signedExpGolomb()
            }
        }
        guard !reader.failed else { return nil }

        return SliceInfo(
            firstMacroblock: firstMacroblock,
            ppsID: ppsID,
            frameNum: frameNum,
            nalType: nalType,
            idrPicID: idrPicID
        )
    }

    private static func rbsp<S: Sequence>(from ebsp: S, limit: Int) -> [UInt8] where S.Element == UInt8 {
        var output: [UInt8] = []
        output.reserveCapacity(min(limit, 512))
        var zeroCount = 0
        for byte in ebsp {
            if output.count >= limit { break }
            if zeroCount >= 2, byte == 0x03 {
                zeroCount = 0
                continue
            }
            output.append(byte)
            if byte == 0 {
                zeroCount += 1
            } else {
                zeroCount = 0
            }
        }
        return output
    }

    private static func skipScalingList(_ reader: inout BitReader, size: Int) -> Bool {
        var lastScale: Int32 = 8
        var nextScale: Int32 = 8
        for _ in 0..<size {
            if nextScale != 0 {
                let delta = reader.signedExpGolomb()
                nextScale = (lastScale + delta + 256) & 255
            }
            if nextScale != 0 { lastScale = nextScale }
            if reader.failed { return false }
        }
        return true
    }
}
