import Foundation
import Observation

/// Live CarPlay Route Guidance feed exported by the patched Carlinkit U2W.
///
/// The adapter exposes normalized JSON at 192.168.50.2.  We intentionally keep
/// this client independent from ScreenCaptureKit/OCR. CarPlay Route Guidance is
/// the only automatic navigation source: when the adapter feed is stale or
/// unavailable, the HUD returns to Freeride instead of falling back to OCR.
@MainActor
@Observable
final class RouteGuidanceAdapterClient {
    enum SourceKind: String, CaseIterable, Hashable {
        case googleMaps = "Google Maps"
        case appleMaps = "Apple Maps"
        case waze = "Waze"
        case other = "Other"

        var priority: Int {
            switch self {
            case .googleMaps: 300
            case .appleMaps: 200
            case .waze: 100
            case .other: 0
            }
        }

        static func classify(_ raw: String) -> SourceKind {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if s.contains("google") { return .googleMaps }
            if s.contains("waze") { return .waze }
            if s.contains("apple") || s == "maps" || s.contains("apple maps") { return .appleMaps }
            return .other
        }
    }

    struct ManeuverSnapshot: Codable, Equatable {
        var index: Int
        var description: String
        var type: Int
        var afterRoad: String
        var distanceMeters: Int
        var displayDistanceText: String
        var drivingSide: Int
    }

    struct Snapshot: Codable, Equatable {
        var version: Int
        var sequence: Int
        var source: String
        var routeState: Int
        var active: Bool
        var currentRoad: String
        var destination: String
        var estimatedArrivalUnixSeconds: Int
        var timeRemainingSeconds: Int
        var distanceRemainingMeters: Int
        var distanceRemainingText: String
        var distanceRemainingUnits: Int
        var distanceToManeuverMeters: Int
        var distanceToManeuverText: String
        var distanceToManeuverUnits: Int
        var currentManeuverIndex: Int?
        var nextManeuverIndex: Int?
        var maneuverCount: Int
        var laneGuidanceShowing: Bool
        var maneuvers: [ManeuverSnapshot]
    }

    private struct TimedSnapshot {
        var snapshot: Snapshot
        var receivedAt: Date
    }

    private let logger: LogManager
    private let navigation: HudNavigationController
    private let endpoint = URL(string: "http://192.168.50.2/cgi-bin/u2wrgd-live.cgi")!
    /// Transport liveness is based on successful HTTP responses, NOT sequence
    /// progression. Apple Maps legitimately holds an unchanged active 0x5201 for
    /// tens of seconds at stoplights and before joining the first routed road.
    private let endpointStaleInterval: TimeInterval = 4.5
    private let pollInterval: Duration = .milliseconds(750)
    private var pollTask: Task<Void, Never>?
    private var snapshots: [SourceKind: TimedSnapshot] = [:]
    private var lastDeliveredSignature = ""
    private var lastEtaMilliseconds: Int64?
    private var selectedKind: SourceKind?
    private var requestCounter = 0
    private var successCounter = 0
    private var lastSequenceBySource: [SourceKind: Int] = [:]
    private var lastSequenceProgressAtBySource: [SourceKind: Date] = [:]
    private var lastEndpointSuccessAt: Date?
    private var lastValidInstruction: NavigationInstruction?
    private var rerouteAwaitingFreshManeuver = false
    private var rerouteCandidateSignature: String?
    private var rerouteCandidateConfirmations = 0
    private var rerouteCandidateLastSequence: Int?
    private var lastRouteState: Int?
    private var rerouteGraceSource: SourceKind?
    private var rerouteGraceUntil: Date?
    private let rerouteGraceInterval: TimeInterval = 3.0

    var onWillActivate: (() -> Void)?
    var onRoadContextChanged: ((CarPlayRouteContext?) -> Void)?

    private(set) var running = false
    private(set) var status = "Adapter feed idle"
    private(set) var selectedSource = "—"
    private(set) var currentRoad = "—"
    private(set) var destination = "—"
    private(set) var etaText = "—"
    private(set) var distanceToManeuverText = "—"
    private(set) var lastError = ""
    private(set) var lastUpdateAt: Date?
    private(set) var lastSequence = 0

    init(logger: LogManager, navigation: HudNavigationController) {
        self.logger = logger
        self.navigation = navigation
    }

    func start(reason: String) {
        guard pollTask == nil else { return }
        running = true
        status = "Connecting to U2W Route Guidance…"
        logger.log("CARPLAY RGD", "Live adapter polling started reason=\(reason) endpoint=\(endpoint.absoluteString)")
        pollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stop(reason: String) {
        pollTask?.cancel()
        pollTask = nil
        running = false
        snapshots.removeAll()
        lastSequenceBySource.removeAll()
        lastSequenceProgressAtBySource.removeAll()
        lastEndpointSuccessAt = nil
        selectedKind = nil
        lastDeliveredSignature = ""
        lastEtaMilliseconds = nil
        lastValidInstruction = nil
        rerouteAwaitingFreshManeuver = false
        rerouteCandidateSignature = nil
        rerouteCandidateConfirmations = 0
        rerouteCandidateLastSequence = nil
        lastRouteState = nil
        rerouteGraceSource = nil
        rerouteGraceUntil = nil
        onRoadContextChanged?(nil)
        selectedSource = "—"
        currentRoad = "—"
        destination = "—"
        etaText = "—"
        distanceToManeuverText = "—"
        status = "Adapter feed stopped"
        navigation.navigationOff(owner: .carPlayAdapter)
        logger.log("CARPLAY RGD", "Live adapter polling stopped reason=\(reason)")
    }

    func refreshNow() {
        Task { @MainActor [weak self] in await self?.pollOnce() }
    }

    private func pollOnce() async {
        requestCounter += 1
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 1.5
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            successCounter += 1
            lastError = ""
            ingest(snapshot, at: Date())
        } catch {
            lastError = error.localizedDescription
            status = "U2W feed unavailable — HUD returned to Freeride"
            pruneAndSelect(now: Date())
            if requestCounter <= 3 || requestCounter % 20 == 0 {
                logger.log("CARPLAY RGD", "Poll failed request=\(requestCounter): \(error.localizedDescription)")
            }
        }
    }

    private func ingest(_ snapshot: Snapshot, at now: Date) {
        let kind = SourceKind.classify(snapshot.source)
        if snapshot.routeState == 5, kind != .other {
            rerouteGraceSource = kind
            rerouteGraceUntil = now.addingTimeInterval(rerouteGraceInterval)
        }
        lastUpdateAt = now
        lastEndpointSuccessAt = now
        lastSequence = snapshot.sequence
        let progressed = lastSequenceBySource[kind] != snapshot.sequence
        if progressed || lastSequenceProgressAtBySource[kind] == nil {
            lastSequenceProgressAtBySource[kind] = now
        }
        lastSequenceBySource[kind] = snapshot.sequence

        // Every successful HTTP response proves that the adapter/runtime is alive.
        // An unchanged sequence simply means the route state did not change.
        snapshots[kind] = TimedSnapshot(snapshot: snapshot, receivedAt: now)
        pruneAndSelect(now: now)
    }

    private func pruneAndSelect(now: Date) {
        snapshots = snapshots.filter { _, timed in
            now.timeIntervalSince(timed.receivedAt) <= endpointStaleInterval
        }

        let candidates = snapshots.compactMap { kind, timed -> (SourceKind, TimedSnapshot)? in
            // Adapter-only policy: only the three requested CarPlay navigation
            // sources are eligible for automatic HUD ownership. A brief routeState
            // 0 is retained only when it follows an observed same-source state 5
            // reroute; ordinary route teardown state 0 still exits Navigation.
            let inRerouteGrace = rerouteGraceSource == kind &&
                (rerouteGraceUntil.map { now <= $0 } ?? false)
            guard kind != .other,
                  (timed.snapshot.active && timed.snapshot.routeState != 0 || inRerouteGrace) else { return nil }
            return (kind, timed)
        }
        .sorted { lhs, rhs in
            if lhs.0.priority != rhs.0.priority { return lhs.0.priority > rhs.0.priority }
            return lhs.1.receivedAt > rhs.1.receivedAt
        }

        guard let winner = candidates.first else {
            if selectedKind != nil {
                logger.log("CARPLAY RGD", "No reachable active Route Guidance source; releasing adapter ownership")
            }
            selectedKind = nil
            selectedSource = "—"
            currentRoad = "—"
            destination = "—"
            etaText = "—"
            distanceToManeuverText = "—"
            lastDeliveredSignature = ""
            lastEtaMilliseconds = nil
            lastValidInstruction = nil
            rerouteAwaitingFreshManeuver = false
            rerouteCandidateSignature = nil
            rerouteCandidateConfirmations = 0
            rerouteCandidateLastSequence = nil
            lastRouteState = nil
            rerouteGraceSource = nil
            rerouteGraceUntil = nil
            onRoadContextChanged?(nil)
            navigation.navigationOff(owner: .carPlayAdapter)
            status = lastError.isEmpty ? "Waiting for active CarPlay route — HUD stays in Freeride" : "U2W feed unavailable — HUD returned to Freeride"
            return
        }

        let kind = winner.0
        let timed = winner.1
        let snapshot = timed.snapshot
        let sourceChanged = selectedKind != kind
        if sourceChanged {
            logger.log(
                "CARPLAY RGD SOURCE",
                "Selected \(kind.rawValue) from live candidates; priority Google Maps > Apple Maps > Waze"
            )
            selectedKind = kind
            lastDeliveredSignature = ""
            lastEtaMilliseconds = nil
            lastValidInstruction = nil
            rerouteAwaitingFreshManeuver = false
            rerouteCandidateSignature = nil
            rerouteCandidateConfirmations = 0
            rerouteCandidateLastSequence = nil
            lastRouteState = nil
            if rerouteGraceSource != kind {
                rerouteGraceSource = nil
                rerouteGraceUntil = nil
            }
        }

        selectedSource = kind == .other ? (snapshot.source.isEmpty ? "Other" : snapshot.source) : kind.rawValue
        currentRoad = snapshot.currentRoad.isEmpty ? "—" : snapshot.currentRoad
        destination = snapshot.destination.isEmpty ? "—" : snapshot.destination
        distanceToManeuverText = displayDistance(snapshot)
        status = "Live Route Guidance • \(selectedSource) • seq \(snapshot.sequence)"

        let primaryManeuver = primaryCurrentManeuver(in: snapshot)
        let nextRoad = primaryManeuver?.afterRoad.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        onRoadContextChanged?(
            CarPlayRouteContext(
                source: selectedSource,
                sequence: snapshot.sequence,
                routeState: snapshot.routeState,
                currentRoad: snapshot.currentRoad,
                nextRoad: nextRoad,
                distanceToManeuverMeters: max(0, snapshot.distanceToManeuverMeters),
                receivedAt: timed.receivedAt
            )
        )

        let enteredReroute = snapshot.routeState == 5 && lastRouteState != 5
        let exitedReroute = snapshot.routeState != 5 && lastRouteState == 5
        if enteredReroute {
            rerouteGraceSource = kind
            rerouteGraceUntil = now.addingTimeInterval(rerouteGraceInterval)
            rerouteAwaitingFreshManeuver = true
            rerouteCandidateSignature = nil
            rerouteCandidateConfirmations = 0
            rerouteCandidateLastSequence = nil
            logger.log(
                "CARPLAY RGD REROUTE",
                "Entered rerouting state seq=\(snapshot.sequence); holding last valid HUD maneuver until a fresh current-maneuver record stabilizes"
            )
        }
        if exitedReroute {
            rerouteAwaitingFreshManeuver = true
            rerouteCandidateSignature = nil
            rerouteCandidateConfirmations = 0
            rerouteCandidateLastSequence = nil
            logger.log(
                "CARPLAY RGD REROUTE",
                "Left explicit rerouting state seq=\(snapshot.sequence) state=\(snapshot.routeState); preserving HUD through 5→0→3→1 transition while waiting for two progressive snapshots of the new current maneuver"
            )
        }
        lastRouteState = snapshot.routeState

        let resolvedInstruction = makeInstruction(snapshot)
        let instruction: NavigationInstruction?
        if snapshot.routeState == 5 {
            // During rerouting, 0x5201 and the most recent 0x5202 table can be
            // temporarily out of phase. Never jump to an old/future table entry.
            instruction = lastValidInstruction
        } else if rerouteAwaitingFreshManeuver {
            if snapshot.routeState == 0 || snapshot.routeState == 3 {
                instruction = lastValidInstruction
            } else if let resolvedInstruction {
                let candidateSignature = instructionIdentity(resolvedInstruction, snapshot: snapshot)
                if rerouteCandidateLastSequence != snapshot.sequence {
                    if rerouteCandidateSignature == candidateSignature {
                        rerouteCandidateConfirmations += 1
                    } else {
                        rerouteCandidateSignature = candidateSignature
                        rerouteCandidateConfirmations = 1
                    }
                    rerouteCandidateLastSequence = snapshot.sequence
                }
                if rerouteCandidateConfirmations >= 2 {
                    rerouteAwaitingFreshManeuver = false
                    rerouteGraceSource = nil
                    rerouteGraceUntil = nil
                    lastValidInstruction = resolvedInstruction
                    instruction = resolvedInstruction
                    logger.log(
                        "CARPLAY RGD REROUTE",
                        "Accepted recalculated current maneuver after \(rerouteCandidateConfirmations) progressive snapshots seq=\(snapshot.sequence) signature=\(candidateSignature)"
                    )
                } else {
                    instruction = lastValidInstruction
                }
            } else {
                instruction = lastValidInstruction
            }
        } else if let resolvedInstruction {
            lastValidInstruction = resolvedInstruction
            instruction = resolvedInstruction
        } else {
            // Missing/0xFFFF current index means the route table is in a short
            // transitional state. Hold the last valid maneuver instead of falling
            // back to maneuver[0], which can belong to the previous route.
            instruction = lastValidInstruction
        }

        guard let instruction else {
            status = "Live Route Guidance • \(selectedSource) • waiting for current maneuver"
            logger.log(
                "CARPLAY RGD HUD",
                "No valid first current maneuver for seq=\(snapshot.sequence) currentIndex=\(snapshot.currentManeuverIndex.map(String.init) ?? "nil") secondCurrent=\(snapshot.nextManeuverIndex.map(String.init) ?? "nil"); HUD remains Freeride until a valid maneuver arrives"
            )
            return
        }

        if !navigation.navigationActive || navigation.feedOwner != .carPlayAdapter || sourceChanged {
            onWillActivate?()
            navigation.navigationOn(owner: .carPlayAdapter)
        }

        let arrivalMs = calculatedArrivalMilliseconds(snapshot)
        if let arrivalMs {
            etaText = Self.formatETA(milliseconds: arrivalMs)
            if shouldSendETA(arrivalMs) {
                navigation.sendETA(arrivalTimeMilliseconds: arrivalMs, owner: .carPlayAdapter)
                lastEtaMilliseconds = arrivalMs
            }
        } else {
            etaText = "—"
        }

        let signature = [
            selectedSource,
            "\(snapshot.sequence)",
            instruction.maneuver.rawValue,
            "\(instruction.distanceMeters)",
            instruction.primaryText,
            instruction.streetName,
            instruction.displayDistanceText
        ].joined(separator: "|")

        // RouteGuidanceUpdate is normally ~1 Hz. Sequence changes are useful for
        // freshness, but avoid spending BLE bandwidth if every HUD-visible field
        // is identical to the previous instruction.
        let visibleSignature = [
            selectedSource,
            instruction.maneuver.rawValue,
            "\(instruction.distanceMeters)",
            instruction.primaryText,
            instruction.streetName,
            instruction.currentStreet
        ].joined(separator: "|")

        if visibleSignature != lastDeliveredSignature {
            navigation.current = instruction
            navigation.sendCurrent(owner: .carPlayAdapter)
            lastDeliveredSignature = visibleSignature
            logger.log(
                "CARPLAY RGD HUD",
                "source=\(selectedSource) seq=\(snapshot.sequence) routeState=\(snapshot.routeState) currentIndex=\(snapshot.currentManeuverIndex.map(String.init) ?? "nil") secondCurrent=\(snapshot.nextManeuverIndex.map(String.init) ?? "nil") maneuver=\(instruction.maneuver.label) distance=\(instruction.distanceMeters)m display=\(instruction.displayDistanceText) street=\(instruction.streetName) eta=\(etaText) signature=\(signature)"
            )
        }
    }

    private func sanitizedCurrentIndex(_ index: Int?) -> Int? {
        guard let index, index >= 0, index < 0xFFFF else { return nil }
        return index
    }

    /// v90.32: the two exported index fields came from CarPlay's current-maneuver
    /// index list. The first index is the HUD's primary/current instruction; the
    /// second can be a simultaneously relevant following instruction. Never prefer
    /// the second index for the primary HUD maneuver.
    private func primaryCurrentManeuver(in snapshot: Snapshot) -> ManeuverSnapshot? {
        guard let index = sanitizedCurrentIndex(snapshot.currentManeuverIndex) else { return nil }
        return snapshot.maneuvers.first(where: { $0.index == index })
    }

    private func instructionIdentity(_ instruction: NavigationInstruction, snapshot: Snapshot) -> String {
        [
            sanitizedCurrentIndex(snapshot.currentManeuverIndex).map(String.init) ?? "nil",
            instruction.maneuver.rawValue,
            instruction.primaryText,
            instruction.streetName,
            instruction.currentStreet
        ].joined(separator: "|")
    }

    private func makeInstruction(_ snapshot: Snapshot) -> NavigationInstruction? {
        guard let maneuver = primaryCurrentManeuver(in: snapshot) else { return nil }

        let mapped = Self.mapManeuverType(maneuver.type)
        let street = !maneuver.afterRoad.isEmpty
            ? maneuver.afterRoad
            : (!maneuver.description.isEmpty ? maneuver.description : snapshot.currentRoad)
        let primary = Self.primaryText(for: maneuver.type, description: maneuver.description, street: street)

        return NavigationInstruction(
            maneuver: mapped,
            distanceMeters: max(0, snapshot.distanceToManeuverMeters > 0 ? snapshot.distanceToManeuverMeters : maneuver.distanceMeters),
            primaryText: primary,
            streetName: street,
            displayDistanceText: displayDistance(snapshot),
            currentStreet: snapshot.currentRoad,
            exitNumber: Self.roundaboutExit(for: maneuver.type)
        )
    }

    private func calculatedArrivalMilliseconds(_ snapshot: Snapshot) -> Int64? {
        // iAP2 exposes both an absolute ETA and TimeRemainingToDestination. Use
        // the absolute phone-provided ETA when present so a cached delta field
        // cannot drift between polls. If it is absent, match the original HUDWAY
        // implementation exactly: ETA = current time + remaining seconds.
        if snapshot.estimatedArrivalUnixSeconds > 1_000_000_000 {
            return Int64(snapshot.estimatedArrivalUnixSeconds) * 1000
        }
        if snapshot.timeRemainingSeconds > 0 && snapshot.timeRemainingSeconds < 7 * 24 * 3600 {
            let now = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
            return now + Int64(snapshot.timeRemainingSeconds) * 1000
        }
        return nil
    }

    private func shouldSendETA(_ value: Int64) -> Bool {
        guard let previous = lastEtaMilliseconds else { return true }
        return abs(value - previous) >= 15_000
    }

    private func displayDistance(_ snapshot: Snapshot) -> String {
        let raw = snapshot.distanceToManeuverText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }
        // Captured CarPlay display-unit values on this U.S. route: 1=miles,
        // 4=feet.  Keep unknown units numeric-data-safe by returning raw text.
        switch snapshot.distanceToManeuverUnits {
        case 1: return raw.contains(" ") ? raw : "\(raw) mi"
        case 4: return raw.contains(" ") ? raw : "\(raw) ft"
        default: return raw
        }
    }

    private static func formatETA(milliseconds: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000.0)
        return d.formatted(date: .omitted, time: .shortened)
    }

    /// Apple's CPManeuverType raw-value map (0...53) collapsed into the native
    /// HUDWAY maneuver vocabulary.
    private static func mapManeuverType(_ type: Int) -> HudManeuver {
        switch type {
        case 1, 20: return .left
        case 2, 21: return .right
        case 3, 5, 11: return .straight
        case 4, 18, 19, 26: return .uTurn
        case 6, 7, 28...46: return .roundabout
        case 8: return .exitRight
        case 9: return .keepRight
        case 10, 12, 24, 25, 27: return .destination
        case 13, 52: return .keepLeft
        case 14, 53: return .keepRight
        case 22: return .exitLeft
        case 23: return .exitRight
        case 47: return .sharpLeft
        case 48: return .sharpRight
        case 49: return .slightLeft
        case 50: return .slightRight
        case 51: return .straight
        default: return .straight
        }
    }

    private static func primaryText(for type: Int, description: String, street: String) -> String {
        let label: String
        switch mapManeuverType(type) {
        case .straight: label = type == 11 ? "Start route" : "Continue"
        case .slightRight: label = "Slight right"
        case .right: label = "Turn right"
        case .sharpRight: label = "Sharp right"
        case .slightLeft: label = "Slight left"
        case .left: label = "Turn left"
        case .sharpLeft: label = "Sharp left"
        case .uTurn: label = "Make a U-turn"
        case .keepRight: label = "Keep right"
        case .keepLeft: label = "Keep left"
        case .exitRight: label = "Take exit right"
        case .exitLeft: label = "Take exit left"
        case .roundabout:
            if let exit = roundaboutExit(for: type) { label = "Roundabout • exit \(exit)" }
            else { label = "Roundabout" }
        case .destination: label = "Arrive at destination"
        }
        if !description.isEmpty, description.lowercased().contains("toward") { return "\(label) \(description)" }
        return label
    }

    private static func roundaboutExit(for type: Int) -> Int? {
        guard (28...46).contains(type) else { return nil }
        return type - 27
    }
}
