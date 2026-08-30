import XCTest
@testable import HUDController

final class V9018NoFlashFastCenterSyncPhillyTests: XCTestCase {
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }

    func testBLEDIMV90172IsDefaultAndTestLabIsOptIn() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let terminal = monitor.components(separatedBy: "private func finalizeBreathSteadyState")[1]
            .components(separatedBy: "private func runStartupAnimationIfNeeded")[0]
        XCTAssertTrue(terminal.contains("power-up breath terminal Power ON"))
        XCTAssertTrue(terminal.contains("power-up breath terminal RGB"))
        XCTAssertTrue(terminal.contains("case .v90172Baseline, .baselineHold:"))
        XCTAssertTrue(terminal.contains("case .brightnessOnlyFinish, .alreadyOnMinimal, .v9018NoFlash:"))

        let prep = monitor.components(separatedBy: "private func queuePowerUpBreath")[1]
            .components(separatedBy: "private func registerPowerOnCohortMember")[0]
        XCTAssertTrue(prep.contains("applyBLEDIMTestStrategyToAutomaticPowerOn ? bledimAnimationStrategy : .v90172Baseline"))
        XCTAssertTrue(prep.contains("case .v9018NoFlash:"))
        XCTAssertTrue(prep.contains("power-up breath preload RGB [18 No-Flash]"))
    }

    func testCenterIsFastDayNightOwnerAndDoorAutoFadeIsOneSecond() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        XCTAssertTrue(monitor.contains("Center presence → Auto brightness ON"))
        XCTAssertTrue(monitor.contains("Center absence → Auto brightness OFF"))
        XCTAssertTrue(monitor.contains("Center present → night Door brightness"))
        XCTAssertTrue(monitor.contains("Center absent → day Door brightness"))
        XCTAssertTrue(monitor.contains("automaticDoorDayNightTransitionSeconds: TimeInterval = 1.0"))
        XCTAssertTrue(monitor.contains("over: automaticDoorDayNightTransitionSeconds"))
        XCTAssertTrue(monitor.contains("Dashboard+Center diagnostic consensus"))
    }

    func testSyncUsesPowerOnCohortBeforeBLEDIMBootSettle() throws {
        let monitor = try source("HUDController/Vehicle/AmbientLightMonitor.swift")
        let run = monitor.components(separatedBy: "private func runStartupAnimationIfNeeded")[1]
            .components(separatedBy: "private func queuePowerUpBreath")[0]
        XCTAssertLessThan(
            run.range(of: "registerPowerOnCohortMember(id)")!.lowerBound,
            run.range(of: "scheduleBLEDIMBootSettleReassert")!.lowerBound
        )
        XCTAssertTrue(monitor.contains("Power-on cohort common T0"))
        XCTAssertTrue(monitor.contains("syncCohortExpectedIDs.isSubset(of: self.synchronizedBreathIDs)"))
        XCTAssertTrue(monitor.contains("synchronizedBreathIDs.isEmpty && syncCohortExpectedIDs.isEmpty"))
    }

    func testRequestedThreeSpeedSourcesAndPhiladelphiaGISArePresent() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("case current = \"Current\""))
        XCTAssertTrue(speed.contains("case traceOSM = \"OSM Trace\""))
        XCTAssertTrue(speed.contains("case improvedTracePhilly = \"Improved + Philly GIS\""))
        XCTAssertFalse(speed.contains("case enhancedOSM = \"Enhanced OSM\""))
        XCTAssertTrue(speed.contains("FeatureServer/\\(layer)/query"))
        XCTAssertTrue(speed.contains("SPEED_LIMITS,SpeedLimits_MPH"))
        XCTAssertTrue(speed.contains("async let residentialTask = fetchPhiladelphiaLayer(1"))
    }

    func testImprovedModeLoadsRoadsWithoutMaxspeedAndClearsStaleSign() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let query = speed.components(separatedBy: "private func updateImprovedSegmentsIfNeeded")[1]
            .components(separatedBy: "private static func makeImprovedSegment")[0]
        XCTAssertTrue(query.contains("way[highway~"))
        XCTAssertFalse(query.contains("[maxspeed]"))
        XCTAssertTrue(query.contains("residential"))
        XCTAssertTrue(speed.contains("improvedDisplayGraceSeconds: TimeInterval = 4.0"))
        XCTAssertTrue(speed.contains("clearDisplayedLimit(reason:"))
    }

    func testImprovedScorerAndMotorwayProtectionAreHardened() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        let scorer = speed.components(separatedBy: "private func traceGeometryMatch")[1]
            .components(separatedBy: "private func bestImprovedTraceSpeedLimit")[0]
        XCTAssertTrue(scorer.contains("var pointBest: Double?"))
        XCTAssertFalse(scorer.contains("Double.greatestFiniteMagnitude"))
        XCTAssertTrue(speed.contains("[\"motorway\", \"motorway_link\"].contains(confirmedOSM.segment.highway)"))
        XCTAssertTrue(speed.contains("source: \"OSM explicit motorway\""))
    }
    func testInferredResidentialFallbackCannotArmWarnings() throws {
        let speed = try source("HUDController/Vehicle/OriginalSpeedLimitEngine.swift")
        XCTAssertTrue(speed.contains("speedWasExplicit: explicitSpeed != nil"))
        XCTAssertTrue(speed.contains("warningEligible: !inferredResidential"))
        XCTAssertTrue(speed.contains("currentLimitWarningEligible"))
        XCTAssertTrue(speed.contains("Display-only inferred speed limit — disable native warning threshold"))
        XCTAssertTrue(speed.contains("Clear stale speed-limit warning threshold"))
        XCTAssertTrue(speed.contains("Speed-limit source changed → native warning OFF until fresh limit"))
    }

}
