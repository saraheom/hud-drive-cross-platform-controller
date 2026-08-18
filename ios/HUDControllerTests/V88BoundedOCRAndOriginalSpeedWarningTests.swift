import XCTest
@testable import HUDController

final class V88BoundedOCRAndOriginalSpeedWarningTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(relative),
            encoding: .utf8
        )
    }

    func testOCRPipelineHasOneWorkerAndOneLatestFrameSlot() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(source.contains("private var pendingOCRImage: UIImage?"))
        XCTAssertTrue(source.contains("private var ocrWorkerTask: Task<Void, Never>?"))
        XCTAssertTrue(source.contains("guard ocrWorkerTask == nil else { return }"))
        XCTAssertTrue(source.contains("pendingOCRImage = image"))
        XCTAssertTrue(source.contains("await self?.runOCRWorker()"))
    }

    func testOldUnboundedPerFrameTaskWasRemoved() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        guard let start = source.range(
            of: "private func process(pixelBuffer: CVPixelBuffer)"
        ),
        let end = source.range(
            of: "private func apply(",
            range: start.upperBound..<source.endIndex
        )
        else {
            XCTFail("process(pixelBuffer:) block not found")
            return
        }

        let body = String(source[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(body.contains("Task {"))
        XCTAssertFalse(body.contains("ExternalNavigationOCRParser.recognize"))
        XCTAssertTrue(body.contains("enqueueLatestOCRImage"))
        XCTAssertTrue(body.contains("captureCIContext.createCGImage"))
    }

    func testManualStopInvalidatesOCRBacklog() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(
            source.contains(
                #"suspendOCRPipeline(reason: "manual Stop Capture")"#
            )
        )
        XCTAssertTrue(source.contains("pendingOCRImage = nil"))
        XCTAssertTrue(source.contains("ocrGeneration += 1"))
        XCTAssertTrue(source.contains("Discarded stale OCR result"))
    }

    func testOCRStallDoesNotRestartHealthyScreenCapture() throws {
        let source = try source(
            "HUDController/Navigation/ExternalNavigationCapture.swift"
        )

        XCTAssertTrue(source.contains("OCR WATCHDOG"))
        XCTAssertTrue(source.contains("if ocrAge > 10"))
        XCTAssertTrue(
            source.contains(
                "OCR worker stalled; raw capture still healthy"
            )
        )
    }

    func testOriginalAutomaticWarningEqualsPostedLimitExactly() throws {
        let source = try source(
            "HUDController/Vehicle/OriginalSpeedLimitEngine.swift"
        )

        XCTAssertTrue(source.contains("SPEED_ALERTS_METHOD=0"))
        XCTAssertTrue(source.contains("SPEED_TOLERANCE_VALUE=0"))
        XCTAssertTrue(
            source.contains(
                "HudCommands.speedWarningThreshold(legalLimitMph)"
            )
        )
        XCTAssertFalse(source.contains("legalLimitMph +"))
        XCTAssertFalse(source.contains("var speedTolerance"))
    }

    func testManualToleranceUIIsGone() throws {
        let source = try source(
            "HUDController/UI/VehicleView.swift"
        )

        XCTAssertFalse(source.contains("Overspeed warning tolerance"))
        XCTAssertFalse(source.contains("speedEngine.speedTolerance"))
        XCTAssertTrue(
            source.contains(
                "Speed warning follows the posted speed limit automatically"
            )
        )
    }
}
