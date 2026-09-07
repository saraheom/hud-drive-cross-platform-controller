import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppState {
    let logger: LogManager
    let bluetooth: HudBluetoothManager
    let navigation: HudNavigationController
    let routeGuidance: RouteGuidanceAdapterClient
    let nowPlaying: CarPlayNowPlayingClient
    let obd: HudOBDController
    let speedEngine: OriginalSpeedLimitEngine
    let ambientLight: AmbientLightMonitor
    let maintenance: HudMaintenanceManager
    let settings = HudSettings()
    private(set) var externalCapture27: Any?
    private var musicFilterInitialized = false
    private var hudRehydrateTask: Task<Void, Never>?
    private var hudReassertTask: Task<Void, Never>?
    private var hudWiFiExposureTask: Task<Void, Never>?
    private var firmwareMaintenanceTask: Task<Void, Never>?

    // v90.34.9 persistent stock-music experiment. Static inspection of the
    // HUDWAY Drive launcher shows MusicNotificationPacket is consumed directly
    // by MainActivity and fed into the stock full/mini music views; there is no
    // public broadcast carrying the parsed metadata. The least-invasive way to
    // test persistence is therefore to reassert the existing native music packet
    // before the launcher's shared notification timeout expires.
    private var persistentMusicTask: Task<Void, Never>?
    private(set) var persistentMusicActive = false
    private(set) var persistentMusicMini = false
    private(set) var persistentMusicStatus = "Persistent music stopped"
    private let persistentMusicRefreshInterval: Duration = .seconds(5)

    // v90.34.5 lane-presentation coordinator. The stock HUD auto-hides lane
    // graphics, so active lanes are reasserted while the selected policy says
    // they should remain visible. No HUD firmware write is involved.
    private var laneGuidanceRefreshTask: Task<Void, Never>?
    private var activeLaneGuidance: [HudCommands.NativeLane] = []
    private var activeLaneDistanceMeters = 0
    private var activeLaneContext = ""
    private var activeLaneIsLive = false
    private var activeLiveLaneManeuverIndex: Int?
    private var activeLiveLaneGuidanceIndex: Int?
    private var activeLiveLaneEventIndex: Int?
    private let laneGuidanceRefreshInterval: Duration = .milliseconds(1500)
    // v90.34.10: safe stock-widget probe for the user's requested right-side
    // lane placement. No firmware/APK write is performed. While active we
    // temporarily replace the normal Navigation dashboard with an isolated
    // side-widget factory probe so a lane packet can reveal whether the stock
    // launcher has any hidden right-side lane-capable renderer.
    private var laneRightSideProbeActive = false

    // Legacy U2W v8.7 fallback cache. v8.7 incorrectly labeled the 0x5204
    // composed-guidance-event id as a route maneuver index and retained only the
    // last event in a pre-cache burst. U2W v8.8 does not use this cache: it
    // resolves the active event on the adapter via 0x5201 InfoType 16.
    private struct LiveLaneCacheEntry: Equatable {
        var laneSequence: Int
        var lanes: [HudCommands.NativeLane]
        var rawSummary: String
    }
    private var liveLaneCacheByManeuver: [Int: LiveLaneCacheEntry] = [:]
    private var liveLaneCurrentManeuverIndex: Int?
    private var liveLaneSource: String?
    private var liveLaneLastRouteState: Int?
    private var liveLaneSessionActive = false
    private var loggedLegacyV87LaneSchema = false

    // HUD Wi-Fi/AP exposure. This uses only stock BLE HUD-mode/hotspot packets;
    // it never sends the SoftwareUpdate start packet or any bytes to TCP/7980.
    private let hudWiFiRecoveryKey = "HUD.WiFiExposureRecoveryNeeded"
    private(set) var hudWiFiExposureActive = false
    private(set) var hudWiFiExposureStatus = "HUD Wi-Fi not forced"
    private(set) var firmwareMaintenanceActive = false

    init() {
        let logger = LogManager()
        self.logger = logger
        let maintenance = HudMaintenanceManager(logger: logger)
        self.maintenance = maintenance
        let bluetooth = HudBluetoothManager(logger: logger)
        self.bluetooth = bluetooth
        let navigation = HudNavigationController(bluetooth: bluetooth, logger: logger)
        let showCurrentStreetKey = "HUD.Settings.navigationShowCurrentStreet"
        navigation.showCurrentStreet = UserDefaults.standard.object(forKey: showCurrentStreetKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: showCurrentStreetKey)
        self.navigation = navigation
        let routeGuidance = RouteGuidanceAdapterClient(logger: logger, navigation: navigation)
        self.routeGuidance = routeGuidance
        let nowPlaying = CarPlayNowPlayingClient(logger: logger)
        self.nowPlaying = nowPlaying
        let obd = HudOBDController(bluetooth: bluetooth, logger: logger)
        self.obd = obd
        routeGuidance.onWillActivate = { [weak obd] in
            obd?.applyNavigationWidgets()
        }
        let speedEngine = OriginalSpeedLimitEngine(bluetooth: bluetooth, logger: logger)
        self.speedEngine = speedEngine
        routeGuidance.onRoadContextChanged = { [weak speedEngine] context in
            speedEngine?.updateCarPlayRouteContext(context)
        }
        let ambientLight = AmbientLightMonitor(bluetooth: bluetooth, logger: logger)
        self.ambientLight = ambientLight
        routeGuidance.onLaneGuidanceChanged = { [weak self] state in
            self?.receiveLiveLaneGuidance(state)
        }
        routeGuidance.onManeuverDelivered = { [weak self] maneuverIndex in
            self?.reassertLiveLaneAfterManeuverDelivery(maneuverIndex: maneuverIndex)
        }
        if #available(iOS 27.0, *) {
            self.externalCapture27 = ExternalNavigationCapture(logger: logger, navigation: self.navigation)
        }

        if UserDefaults.standard.bool(forKey: hudWiFiRecoveryKey) {
            hudWiFiExposureStatus = "Wi-Fi release armed for next HUD BLE connection"
        }

        obd.onConnectionChanged = { [weak self, weak ambientLight] connected in
            // OBD remains useful telemetry/diagnostic state, but v90.29 no longer
            // uses it as permission for ambient animation. HUD transport readiness
            // is the reliable automatic-animation session gate.
            ambientLight?.obdPowerSignal(connected)
        }

        speedEngine.onSpeedStateChanged = { [weak ambientLight] speedMph, limitMph, available in
            ambientLight?.updateOverspeedWarning(
                gpsSpeedMph: speedMph,
                speedLimitMph: limitMph,
                limitAvailable: available
            )
        }

        nowPlaying.onTrackChanged = { [weak self] artist, track in
            self?.pushNowPlayingMetadataToHUD(artist: artist, track: track)
        }

        bluetooth.onTransportReady = { [weak self] in
            guard let self else { return }
            self.ambientLight.hudTransportPowerSignal(true)
            self.speedEngine.primeRectangularStyle()
            self.routeGuidance.start(reason: "HUD BLE transport ready")
            self.nowPlaying.start(reason: "HUD BLE transport ready")

            if UserDefaults.standard.bool(forKey: self.hudWiFiRecoveryKey),
               !self.hudWiFiExposureActive {
                self.disableHUDWiFiExposure(reason: "BLE transport recovery")
            }

            self.scheduleHUDRehydration(reason: "BLE transport ready")
        }

        bluetooth.onHUDSessionReset = { [weak self] in
            guard let self else { return }
            self.speedEngine.primeRectangularStyle()
            self.scheduleHUDRehydration(reason: "HUD firmware hello / physical session reset")
        }

        bluetooth.onTransportDisconnected = { [weak self] in
            guard let self else { return }
            // Ambient animation is gated by the actual HUD transport session.
            // Any HUD disconnect closes that gate; courtesy lights may remain on,
            // but automatic Breath waits for the next HUD transport connection.
            self.ambientLight.hudTransportPowerSignal(false)
            self.hudRehydrateTask?.cancel()
            self.hudRehydrateTask = nil
            self.hudReassertTask?.cancel()
            self.hudReassertTask = nil
            self.laneGuidanceRefreshTask?.cancel()
            self.laneGuidanceRefreshTask = nil
            self.laneRightSideProbeActive = false
            self.hudWiFiExposureTask?.cancel()
            self.hudWiFiExposureTask = nil
            self.firmwareMaintenanceTask?.cancel()
            self.firmwareMaintenanceTask = nil
            self.stopPersistentMusic(sendRestorePackets: false, reason: "HUD BLE transport disconnected")
            if self.firmwareMaintenanceActive {
                self.firmwareMaintenanceActive = false
                self.maintenance.disconnectADB()
            }
            if self.hudWiFiExposureActive {
                self.hudWiFiExposureActive = false
                self.hudWiFiExposureStatus = "BLE lost — Wi-Fi release armed for reconnect"
                UserDefaults.standard.set(true, forKey: self.hudWiFiRecoveryKey)
            }
            self.obd.transportDisconnected()
            self.routeGuidance.stop(reason: "HUD BLE transport disconnected")
            self.nowPlaying.stop(reason: "HUD BLE transport disconnected")
            self.logger.log(
                "HUD SESSION",
                "BLE transport disconnected; Route Guidance polling stopped and HUD returned to Freeride"
            )
        }

    }

    /// The original HUDWAY protocol separates dashboard profile configuration
    /// (`HudWidgetCommandPacket`, type 0/1) from the active Navigation/Freeride
    /// mode (`navigationState`). Rehydrating both profiles must therefore finish by
    /// restoring the actual active mode; otherwise a firmware/session reset can
    /// leave the HUD center presentation in the wrong state even though the
    /// Freeride type-0 profile itself is correct.
    private func restoreDashboardOperatingMode(reason: String) {
        guard bluetooth.state == .connected else { return }
        if navigation.navigationActive {
            bluetooth.enqueue(
                HudCommands.navigationState(true),
                label: "Restore dashboard mode → Navigation ON"
            )
            // The CarPlay adapter feed owns maneuver re-delivery. Do not
            // fabricate/resend the controller's default instruction.
            logger.log("DASHBOARD MODE", "Restored Navigation ON after profile rehydration reason=\(reason)")
        } else {
            bluetooth.enqueue(
                HudCommands.navigationState(false),
                label: "Restore dashboard mode → Freeride (Navigation OFF)"
            )
            logger.log(
                "DASHBOARD MODE",
                "Restored original Freeride active mode via Navigation OFF after profile rehydration reason=\(reason)"
            )
        }
    }


    func initializeHUD() {
        logger.log("APP", "Initialize HUD requested")
        bluetooth.initializeHUD()
    }

    /// Persistent top-bar shortcut for adapter-only CarPlay Route Guidance.
    /// It never starts ScreenCaptureKit and never forces Navigation ON without
    /// a fresh active adapter route. If the feed is absent, HUD remains Freeride.
    func quickStartNavigation() {
        logger.log("QUICK ACTION", "Navigation shortcut tapped — adapter-only Route Guidance refresh")
        routeGuidance.start(reason: "Navigation shortcut")
        routeGuidance.refreshNow()
    }

    /// Persistent top-bar shortcut: refresh the passive CarPlay Now Playing feed.
    /// No media-app authorization or app switching is required.
    func quickRefreshNowPlaying() {
        logger.log("QUICK ACTION", "Music shortcut tapped — CarPlay Now Playing refresh")
        nowPlaying.refreshNow()
    }

    func applyBrightness() {
        // v90.16: when ambient headlight automation owns HUD Auto Brightness,
        // do not let the generic persisted HUD setting fight that consensus during
        // rehydration or a settings refresh. rehydrateHUDState()/headlight edges
        // are the single owner until the ambient trigger is disabled.
        if ambientLight.enabled && ambientLight.hudBrightnessTriggerEnabled {
            logger.log(
                "HUD BRIGHTNESS",
                "Generic brightness apply deferred — ambient headlight consensus owns HUD Auto Brightness"
            )
            return
        }

        bluetooth.enqueue(HudCommands.autoBrightness(settings.autoBrightness), label: "Auto brightness \(settings.autoBrightness)")
        if !settings.autoBrightness {
            bluetooth.enqueue(HudCommands.manualBrightness(settings.brightness), label: "Brightness \(settings.brightness)")
        }
    }

    func applyTimeWeather() {
        bluetooth.enqueue(HudCommands.timeWeather(settings.showTimeWeather), label: "Time/weather \(settings.showTimeWeather)")
    }


    func applyColorTheme() {
        bluetooth.enqueue(
            HudCommands.baseColor(settings.colorTheme),
            label: "HUD color theme \(settings.colorTheme.rawValue) \(settings.colorTheme.originalWireValue)"
        )
        logger.log(
            "HUD COLOR",
            "Applied \(settings.colorTheme.rawValue) raw=\(settings.colorTheme.originalWireValue)"
        )
    }


    func applyNotificationSettings() {
        logger.log("NOTIFICATION", "Applying HUD ANCS notification filter settings")

        bluetooth.enqueue(
            HudCommands.notificationSettingsInit(),
            label: "Notification filter init"
        )
        bluetooth.enqueue(
            HudCommands.notificationsMasterEnabled(true),
            label: "Notifications master ON"
        )
        bluetooth.enqueue(
            HudCommands.notificationTimeout(seconds: settings.notificationExposureSeconds),
            label: "Notification timeout \(settings.notificationExposureSeconds)s"
        )
        bluetooth.enqueue(
            HudCommands.notificationLineCount(settings.notificationLines),
            label: "Notification lines \(settings.notificationLines)"
        )

        bluetooth.enqueue(
            HudCommands.musicNotificationFilter(enabled: settings.notifyMusic),
            label: "Music notification popups \(settings.notifyMusic ? "ON" : "OFF")"
        )
        musicFilterInitialized = settings.notifyMusic

        if settings.notifyAll {
            logger.log("NOTIFICATION", "All notifications mode enabled")
            return
        }

        let selections: [(HudNotificationKind, Bool)] = [
            (.calls, settings.notifyCalls),
            (.messages, settings.notifyMessages),
            (.calendar, settings.notifyCalendar),
            (.gmail, settings.notifyGmail),
            (.weChat, settings.notifyWeChat),
            (.kakaoTalk, settings.notifyKakaoTalk)
        ]

        for (kind, enabled) in selections where enabled {
            logger.log(
                "NOTIFICATION FILTER",
                "\(kind.displayName): \(kind.identifiers.joined(separator: ", "))"
            )
            bluetooth.enqueue(
                HudCommands.notificationFilter(
                    enabled: true,
                    textColor: kind.textColor,
                    icon: kind.hudIcon,
                    identifiers: kind.identifiers
                ),
                label: "Notification filter \(kind.displayName)"
            )
        }
    }

    func applyDashboardPreset() {
        let p = settings.selectedPreset
        if p.name == "Freeride" {
            // The original HUDWAY Freeride mode is the type=0 dashboard packet
            // with center=Simple and user-selectable side widgets. Route the
            // generic Dashboard preset through that exact implementation so the
            // Dashboard screen cannot replace the original center RPM/bar UI with
            // the older approximation (`center=Speedo`).
            obd.applyFreerideWidgets()
            logger.log("DASHBOARD", "Freeride preset routed to original type=0 center=Simple implementation")
            return
        }
        bluetooth.enqueue(
            HudCommands.dashboard(left: p.left, center: p.center, right: p.right, navigationLayout: p.navigationLayout),
            label: "Dashboard \(p.name)"
        )
    }



    // MARK: - Navigation presentation / lane guidance

    var laneGuidanceThresholdMeters: Int {
        Int((settings.laneGuidanceDistanceMiles * 1609.344).rounded())
    }

    func receiveLiveLaneGuidance(_ state: RouteGuidanceAdapterClient.LiveLaneGuidanceState?) {
        guard let state else {
            guard liveLaneSessionActive else { return }
            logger.log("CARPLAY LANE", "Live Route Guidance ended; clearing live lane state")
            liveLaneSessionActive = false
            liveLaneCacheByManeuver.removeAll()
            liveLaneCurrentManeuverIndex = nil
            liveLaneSource = nil
            liveLaneLastRouteState = nil
            activeLiveLaneGuidanceIndex = nil
            activeLiveLaneEventIndex = nil
            if activeLaneIsLive {
                clearLaneGuidancePolicy(reason: "live Route Guidance inactive")
            }
            return
        }

        liveLaneSessionActive = true

        if liveLaneSource != state.source {
            if let previous = liveLaneSource {
                logger.log("CARPLAY LANE", "Source changed \(previous) → \(state.source); dropping old live lane state")
            }
            liveLaneCacheByManeuver.removeAll()
            liveLaneCurrentManeuverIndex = nil
            activeLiveLaneGuidanceIndex = nil
            activeLiveLaneEventIndex = nil
            if activeLaneIsLive {
                clearLaneGuidancePolicy(reason: "CarPlay source changed")
            }
            liveLaneSource = state.source
        }

        let enteredReroute = state.routeState == 5 && liveLaneLastRouteState != 5
        if enteredReroute {
            liveLaneCacheByManeuver.removeAll()
            liveLaneCurrentManeuverIndex = nil
            activeLiveLaneGuidanceIndex = nil
            activeLiveLaneEventIndex = nil
            if activeLaneIsLive {
                clearLaneGuidancePolicy(reason: "CarPlay reroute started")
            }
            logger.log("CARPLAY LANE", "Reroute state 5 entered; old lane state cleared")
        }
        liveLaneLastRouteState = state.routeState

        // Google Maps can transiently move the exported maneuver cursor backward
        // while its route table stabilizes. v90.34.6 treated every backward move
        // as a new route and repeatedly deleted valid lane data. Cursor movement
        // is now diagnostic only; explicit source/reroute/session evidence owns
        // lane-session resets.
        if let currentIndex = state.currentManeuverIndex,
           liveLaneCurrentManeuverIndex != currentIndex {
            let previous = liveLaneCurrentManeuverIndex.map(String.init) ?? "nil"
            liveLaneCurrentManeuverIndex = currentIndex
            logger.log(
                "CARPLAY LANE CURSOR",
                "current maneuver \(previous) → \(currentIndex) routeSeq=\(state.routeSequence) distance=\(state.distanceToManeuverMeters)m (no cache reset on cursor wobble)"
            )
        }

        if state.schemaVersion >= 2 {
            receiveResolvedV88LaneGuidance(state)
        } else {
            receiveLegacyV87LaneGuidance(state)
        }
    }

    /// U2W v8.8 resolves the protocol correctly on the adapter:
    /// 0x5204 TLV1 is a composedGuidanceEventIndex and 0x5201 InfoType 16
    /// selects the active event from that cache. The iPhone therefore consumes
    /// the already-resolved current lane event instead of guessing a mapping to
    /// the independently moving route-maneuver cursor.
    private func receiveResolvedV88LaneGuidance(_ state: RouteGuidanceAdapterClient.LiveLaneGuidanceState) {
        // The physical Google Maps capture establishes two distinct concepts:
        //   * 0x5204 events may be pre-cached well before they are needed.
        //   * 0x5201 InfoType 16 selects an event, while InfoType 18 says whether
        //     CarPlay is actively presenting that event right now.
        // A selector value of 0 is both a valid event id and the value observed
        // when Google Maps hides lane guidance. Therefore laneGuidanceShowing is
        // the activation edge; Persistent/Near-turn policy may keep an already
        // activated event after that flag falls, but a hidden selector must never
        // replace the latched event with cached event 0.
        let currentIndex = state.currentManeuverIndex

        if state.routeState == 0 {
            if activeLaneIsLive {
                clearLaneGuidancePolicy(reason: "v8.8 route ended")
            }
            return
        }

        if state.laneGuidanceShowing {
            guard let currentIndex else {
                logger.log(
                    "CARPLAY LANE RESOLVE",
                    "showing=1 but current route maneuver is unresolved routeSeq=\(state.routeSequence); waiting before latching lanes"
                )
                return
            }
            guard let selectedIndex = state.laneGuidanceIndex else {
                logger.log(
                    "CARPLAY LANE RESOLVE",
                    "showing=1 but v8.8 selector missing routeSeq=\(state.routeSequence) current=\(String(currentIndex))"
                )
                if activeLaneIsLive,
                   let activeManeuver = activeLiveLaneManeuverIndex,
                   activeManeuver != currentIndex {
                    clearLaneGuidancePolicy(reason: "new maneuver has no resolved v8.8 selector")
                }
                return
            }

            guard !state.lanes.isEmpty,
                  let laneSequence = state.laneSequence else {
                // The selector can precede its matching pre-cached 0x5204 packet.
                // Never substitute another cached event. If the route cursor has
                // already advanced, remove the old maneuver's lanes while waiting.
                if activeLaneIsLive,
                   let activeManeuver = activeLiveLaneManeuverIndex,
                   activeManeuver != currentIndex {
                    clearLaneGuidancePolicy(reason: "v8.8 selected event not resolved for new maneuver")
                }
                logger.log(
                    "CARPLAY LANE RESOLVE",
                    "showing=1 selector=\(selectedIndex) unresolved routeSeq=\(state.routeSequence) current=\(String(currentIndex))"
                )
                return
            }

            let eventIndex = state.laneGuidanceEventIndex ?? selectedIndex
            if eventIndex != selectedIndex {
                logger.log(
                    "CARPLAY LANE RESOLVE",
                    "selector/event mismatch selector=\(selectedIndex) event=\(eventIndex); accepting exporter-resolved event"
                )
            }

            let context = "Live U2W v8.8 \(state.source) guidance=\(selectedIndex) event=\(eventIndex) laneSeq=\(laneSequence)"
            let changed = !activeLaneIsLive ||
                activeLiveLaneGuidanceIndex != selectedIndex ||
                activeLiveLaneEventIndex != eventIndex ||
                activeLiveLaneManeuverIndex != currentIndex ||
                activeLaneGuidance != state.lanes

            activeLiveLaneGuidanceIndex = selectedIndex
            activeLiveLaneEventIndex = eventIndex
            activeLiveLaneManeuverIndex = currentIndex

            if changed {
                setLaneGuidanceForCurrentManeuver(
                    state.lanes,
                    distanceMeters: state.distanceToManeuverMeters,
                    context: context,
                    isLive: true
                )
                // setLaneGuidanceForCurrentManeuver intentionally preserves the
                // live maneuver binding populated above.
                activeLiveLaneManeuverIndex = currentIndex
                logger.log(
                    "CARPLAY LANE ACTIVATE",
                    "v8.8 selector=\(selectedIndex) event=\(eventIndex) maneuver=\(String(currentIndex)) laneSeq=\(laneSequence) distance=\(state.distanceToManeuverMeters)m policy=\(settings.laneGuidanceMode.title) showingFlag=1 values=[\(state.lanes.map { String($0.wireValue) }.joined(separator: ","))]"
                )
            } else {
                updateActiveLaneDistanceMeters(state.distanceToManeuverMeters, context: context)
            }
            return
        }

        // CarPlay hid its stock lane layer. For custom Persistent/Near-turn
        // behavior, retain the last event only while we are still on the same
        // route maneuver. This is what makes Persistent actually persist without
        // allowing Google Maps' hidden selector=0 to overwrite the active event.
        if activeLaneIsLive {
            if let activeManeuver = activeLiveLaneManeuverIndex,
               let currentIndex,
               activeManeuver != currentIndex {
                logger.log(
                    "CARPLAY LANE LIFETIME",
                    "maneuver advanced \(activeManeuver) → \(currentIndex) while showing=0; clearing latched event guidance=\(activeLiveLaneGuidanceIndex.map(String.init) ?? "nil")"
                )
                clearLaneGuidancePolicy(reason: "live lane maneuver completed")
            } else {
                updateActiveLaneDistanceMeters(
                    state.distanceToManeuverMeters,
                    context: activeLaneContext
                )
                logger.log(
                    "CARPLAY LANE LATCH",
                    "showing=0 selector=\(state.laneGuidanceIndex.map(String.init) ?? "nil") ignored; keeping event=\(activeLiveLaneEventIndex.map(String.init) ?? "nil") maneuver=\(activeLiveLaneManeuverIndex.map(String.init) ?? "nil") policy=\(settings.laneGuidanceMode.title)"
                )
            }
        }
    }

    /// Backward-compatible fallback for U2W v8.7. That exporter incorrectly
    /// labeled the 0x5204 composed event id as maneuverIndex and retained only
    /// the last event of a burst, so complete live lane behavior is impossible
    /// with v8.7. Keep the old best-effort mapping without allowing transient
    /// backward cursor movement to wipe the cache.
    private func receiveLegacyV87LaneGuidance(_ state: RouteGuidanceAdapterClient.LiveLaneGuidanceState) {
        if !loggedLegacyV87LaneSchema {
            loggedLegacyV87LaneSchema = true
            logger.log("CARPLAY LANE", "U2W v8.7 lane schema detected; best-effort only — install v8.8 for active-event resolution")
        }

        if !state.lanes.isEmpty,
           let laneSequence = state.laneSequence,
           let laneIndex = state.laneManeuverIndex ?? state.currentManeuverIndex {
            let entry = LiveLaneCacheEntry(
                laneSequence: laneSequence,
                lanes: state.lanes,
                rawSummary: state.rawSummary
            )
            if liveLaneCacheByManeuver[laneIndex] != entry {
                liveLaneCacheByManeuver[laneIndex] = entry
                logger.log(
                    "CARPLAY LANE CACHE",
                    "legacy-v8.7 routeSeq=\(state.routeSequence) laneSeq=\(laneSequence) legacyIndex=\(laneIndex) values=[\(state.lanes.map { String($0.wireValue) }.joined(separator: ","))]"
                )
            }
        }

        guard let currentIndex = state.currentManeuverIndex,
              let cached = liveLaneCacheByManeuver[currentIndex] else { return }

        let context = "Legacy U2W v8.7 \(state.source) index=\(currentIndex) laneSeq=\(cached.laneSequence)"
        if !activeLaneIsLive || activeLiveLaneManeuverIndex != currentIndex || activeLaneGuidance != cached.lanes {
            activeLiveLaneManeuverIndex = currentIndex
            setLaneGuidanceForCurrentManeuver(
                cached.lanes,
                distanceMeters: state.distanceToManeuverMeters,
                context: context,
                isLive: true
            )
        } else {
            updateActiveLaneDistanceMeters(state.distanceToManeuverMeters, context: context)
        }
    }

    private func reassertLiveLaneAfterManeuverDelivery(maneuverIndex: Int?) {
        guard bluetooth.state == .connected,
              activeLaneIsLive,
              shouldDisplayActiveLanes(),
              let activeManeuver = activeLiveLaneManeuverIndex,
              let maneuverIndex,
              activeManeuver == maneuverIndex else { return }
        // The stock firmware can clear the lane layer when the maneuver packet
        // redraws. Re-send lanes in the same BLE queue immediately after every
        // delivery of the *same* maneuver that owns the latched lane event. A
        // newly advanced maneuver must never receive the previous turn's lanes.
        sendActiveLaneGuidance(label: "Lane policy → post-maneuver reassert")
        logger.log(
            "CARPLAY LANE REASSERT",
            "after maneuver delivery index=\(maneuverIndex) guidance=\(activeLiveLaneGuidanceIndex.map(String.init) ?? "nil")"
        )
    }

    private func updateActiveLaneDistanceMeters(_ distanceMeters: Int, context: String) {
        let wasVisible = shouldDisplayActiveLanes()
        activeLaneDistanceMeters = max(0, distanceMeters)
        activeLaneContext = context
        let isVisible = shouldDisplayActiveLanes()
        if wasVisible != isVisible {
            logger.log(
                "HUD LANE POLICY",
                "distance gate crossed distance=\(activeLaneDistanceMeters)m threshold=\(laneGuidanceThresholdMeters)m visible=\(isVisible)"
            )
            reevaluateActiveLaneGuidance(reason: "live distance threshold crossed")
        }
    }

    func applyNavigationPresentationSettings() {
        navigation.showCurrentStreet = settings.navigationShowCurrentStreet
        logger.log(
            "NAV PRESENTATION",
            "currentStreet=\(settings.navigationShowCurrentStreet ? "ON" : "OFF") lanes=\(settings.laneGuidanceMode.title) threshold=\(String(format: "%.1f", settings.laneGuidanceDistanceMiles))mi placement=\(settings.lanePlacementMode.title)"
        )

        // Re-send the currently visible maneuver so the current-street toggle is
        // immediately observable during parked replay and normal navigation.
        if bluetooth.state == .connected, navigation.navigationActive {
            navigation.sendCurrent(owner: navigation.feedOwner)
        }
        reevaluateActiveLaneGuidance(reason: "settings changed")
    }

    private func shouldDisplayActiveLanes() -> Bool {
        guard !activeLaneGuidance.isEmpty else { return false }
        switch settings.laneGuidanceMode {
        case .off:
            return false
        case .persistent:
            return true
        case .nearTurn:
            return activeLaneDistanceMeters <= laneGuidanceThresholdMeters
        }
    }

    private func reevaluateActiveLaneGuidance(reason: String) {
        laneGuidanceRefreshTask?.cancel()
        laneGuidanceRefreshTask = nil

        guard bluetooth.state == .connected else { return }
        guard shouldDisplayActiveLanes() else {
            bluetooth.enqueue(HudCommands.clearLaneGuidance(), label: "Lane policy → clear (\(reason))")
            restoreNormalNavigationAfterLaneProbeIfNeeded(reason: "lane hidden: \(reason)")
            logger.log(
                "HUD LANE POLICY",
                "hidden reason=\(reason) mode=\(settings.laneGuidanceMode.title) distance=\(activeLaneDistanceMeters)m threshold=\(laneGuidanceThresholdMeters)m placement=\(settings.lanePlacementMode.title)"
            )
            return
        }

        if settings.lanePlacementMode == .centerNative {
            restoreNormalNavigationAfterLaneProbeIfNeeded(reason: "center-native selected")
        } else {
            activateRightLaneWidgetProbeIfNeeded(reason: reason)
        }

        sendActiveLaneGuidance(label: "Lane policy → show (\(reason))")
        laneGuidanceRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.laneGuidanceRefreshInterval)
                guard !Task.isCancelled,
                      self.bluetooth.state == .connected,
                      self.navigation.navigationActive,
                      self.shouldDisplayActiveLanes() else { break }
                self.sendActiveLaneGuidance(label: "Lane policy → persistence refresh")
            }
        }
    }

    private func activateRightLaneWidgetProbeIfNeeded(reason: String) {
        guard !laneRightSideProbeActive,
              navigation.navigationActive,
              let rightWidget = settings.lanePlacementMode.rightWidgetName else { return }

        laneRightSideProbeActive = true
        // Static firmware inspection shows setLaneInstructions() fans the same
        // lane list to center/left/right widgets. Keep the proven center
        // Navigation widget in place for a safe road test, while temporarily
        // replacing the normal right-side ETA with the selected candidate. If
        // that candidate implements lanes, we should see a second/right-side
        // response. The center gray lane box may still appear during this probe
        // because the stock command cannot address one widget independently.
        bluetooth.enqueue(
            HudCommands.dashboard(
                left: obd.navigationLeft.rawValue,
                center: "Navigation",
                right: rightWidget,
                navigationLayout: true
            ),
            label: "Lane right-side probe → \(rightWidget)"
        )
        logger.log(
            "HUD LANE PROBE",
            "activate right=\(rightWidget) replaces ETA center=Navigation reason=\(reason); stock-only/no filesystem write"
        )

        // setWidgets() creates a fresh widget and hydrates cached values, but
        // explicitly re-send the current maneuver so any hidden side navigation
        // implementation receives the same native maneuver state before lanes.
        navigation.sendCurrent(owner: navigation.feedOwner)
    }

    private func restoreNormalNavigationAfterLaneProbeIfNeeded(reason: String) {
        guard laneRightSideProbeActive else { return }
        laneRightSideProbeActive = false
        guard bluetooth.state == .connected else { return }
        obd.applyNavigationWidgets()
        if navigation.navigationActive {
            navigation.sendCurrent(owner: navigation.feedOwner)
        }
        logger.log(
            "HUD LANE PROBE",
            "restore normal Navigation dashboard right=\(obd.navigationRight.rawValue) reason=\(reason)"
        )
    }

    private func sendActiveLaneGuidance(label: String) {
        bluetooth.enqueue(HudCommands.laneGuidance(activeLaneGuidance), label: label)
        logger.log(
            "HUD LANE POLICY",
            "show context=\(activeLaneContext) mode=\(settings.laneGuidanceMode.title) distance=\(activeLaneDistanceMeters)m values=\(activeLaneGuidance.map { String($0.wireValue) }.joined(separator: ","))"
        )
    }

    func setLaneGuidanceForCurrentManeuver(
        _ lanes: [HudCommands.NativeLane],
        distanceMeters: Int,
        context: String,
        isLive: Bool = false
    ) {
        activeLaneGuidance = lanes
        activeLaneDistanceMeters = max(0, distanceMeters)
        activeLaneContext = context
        activeLaneIsLive = isLive
        if !isLive {
            activeLiveLaneManeuverIndex = nil
        }
        reevaluateActiveLaneGuidance(reason: "new lane data")
    }

    func clearLaneGuidancePolicy(reason: String = "manual clear") {
        laneGuidanceRefreshTask?.cancel()
        laneGuidanceRefreshTask = nil
        activeLaneGuidance = []
        activeLaneDistanceMeters = 0
        activeLaneContext = ""
        activeLaneIsLive = false
        activeLiveLaneManeuverIndex = nil
        activeLiveLaneGuidanceIndex = nil
        activeLiveLaneEventIndex = nil
        guard bluetooth.state == .connected else {
            laneRightSideProbeActive = false
            return
        }
        bluetooth.enqueue(HudCommands.clearLaneGuidance(), label: "Lane guidance clear")
        restoreNormalNavigationAfterLaneProbeIfNeeded(reason: "lane policy cleared: \(reason)")
        logger.log("HUD LANE POLICY", "clear reason=\(reason)")
    }

    // MARK: - HUD Wi-Fi / casting network exposure

    var hudWiFiExpectedSSID: String {
        bluetooth.connectedName ?? bluetooth.savedHUDName ?? "HUDWAY Drive"
    }

    func enableHUDWiFiExposure() {
        guard bluetooth.state == .connected else {
            hudWiFiExposureStatus = "Connect the HUD over BLE first"
            return
        }

        hudWiFiExposureTask?.cancel()
        hudWiFiExposureActive = true
        hudWiFiExposureStatus = "Starting stock 5-GHz HUDWAY AP…"
        UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)

        // Physical stock-app log, HUD FW 1.1.27:
        //   HudHotspotBaseband(is5G:true, forceEnable:false)
        //   KivicMode(5)
        // Then HudLauncher itself starts WifiApEnabler ~2.6 s later, hostapd,
        // tethering/dnsmasq, and wlan0=192.168.43.1. Do NOT return to mode 4
        // during this bootstrap; v90.34.5.2 did so at 1.8 s and aborted it.
        logger.log(
            "HUD WIFI",
            "Stock AP bootstrap: 5GHz force=false → IOS_KIVICCAST_MODE(5); hold mode 5 for full SoftAP/DHCP startup"
        )
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false),
            label: "HUD Wi-Fi → stock 5GHz baseband (force OFF)"
        )
        bluetooth.enqueue(HudCommands.kivicMode(5), label: "HUD Wi-Fi → stock iOS KivicCast mode 5")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → bootstrap KeepAlive")

        hudWiFiExposureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(5000))
            guard !Task.isCancelled, self.hudWiFiExposureActive,
                  self.bluetooth.state == .connected else { return }
            // Stay in mode 5 for the whole maintenance session. Physical testing
            // proved forceEnable=true tears the SoftAP down, so that experiment is retired.
            self.hudWiFiExposureStatus = "Stock AP startup complete — join HUDWAY Wi-Fi; mode 5 held"
            self.bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → post-bootstrap KeepAlive")
            self.hudWiFiExposureTask = nil
        }
    }

    /// Re-run the exact stock AP bootstrap and remain in IOS_KIVICCAST_MODE(5).
    func holdHUDWiFiCastingModeForDiagnostics() {
        guard bluetooth.state == .connected else {
            hudWiFiExposureStatus = "Connect the HUD over BLE first"
            return
        }
        hudWiFiExposureTask?.cancel()
        hudWiFiExposureActive = true
        UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)
        logger.log("HUD WIFI", "Diagnostic: restart exact stock 5GHz force=false + IOS_KIVICCAST_MODE(5)")
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false),
            label: "HUD Wi-Fi diagnostic → stock 5GHz baseband"
        )
        bluetooth.enqueue(HudCommands.kivicMode(5), label: "HUD Wi-Fi diagnostic → hold iOS KivicCast mode 5")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi diagnostic → KeepAlive")
        hudWiFiExposureStatus = "Stock cast mode 5 held — allow ~5 s, then reconnect laptop"
        hudWiFiExposureTask = nil
    }

    func disableHUDWiFiExposure(reason: String = "manual") {
        hudWiFiExposureTask?.cancel()
        hudWiFiExposureTask = nil
        hudWiFiExposureActive = false
        guard bluetooth.state == .connected else {
            hudWiFiExposureStatus = "HUD disconnected — Wi-Fi release armed for reconnect"
            UserDefaults.standard.set(true, forKey: hudWiFiRecoveryKey)
            return
        }
        // Match the stock OFF transition captured from the original HUDWAY app.
        logger.log("HUD WIFI", "Disable HUD AP reason=\(reason): stock 5GHz force=false + IOS_HUD_MODE(4)")
        bluetooth.enqueue(
            HudCommands.hudHotspotBaseband(is5G: true, forceEnable: false),
            label: "HUD Wi-Fi → stock AP release"
        )
        bluetooth.enqueue(HudCommands.kivicMode(4), label: "HUD Wi-Fi → restore iOS HUD mode 4")
        bluetooth.enqueue(HudCommands.fullScreen(true), label: "HUD Wi-Fi → full screen ON")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "HUD Wi-Fi → KeepAlive")
        UserDefaults.standard.set(false, forKey: hudWiFiRecoveryKey)
        hudWiFiExposureStatus = "HUD Wi-Fi released"
    }

    // MARK: - HUD firmware maintenance / boot animation override

    func startFirmwareMaintenance() {
        guard bluetooth.state == .connected else {
            maintenance.status = "Connect the HUD over BLE first"
            return
        }
        firmwareMaintenanceTask?.cancel()
        stopPersistentMusic(sendRestorePackets: true, reason: "firmware maintenance started")
        firmwareMaintenanceActive = true
        routeGuidance.stop(reason: "HUD firmware maintenance Wi-Fi")
        nowPlaying.stop(reason: "HUD firmware maintenance Wi-Fi")
        enableHUDWiFiExposure()
        logger.log("HUD MAINT", "Starting boot-animation maintenance: stock 5GHz force=false mode 5")

        let ssid = hudWiFiExpectedSSID
        firmwareMaintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(5400))
            guard !Task.isCancelled, self.firmwareMaintenanceActive,
                  self.bluetooth.state == .connected else { return }
            self.maintenance.status = "HUD AP ready. Join \(ssid) (password 87654321) in iPhone Wi-Fi Settings, then return and tap Reconnect ADB."
            // Try ADB once in case iOS already re-associated with the remembered HUD network.
            do {
                try await self.maintenance.connectADB(retries: 2)
            } catch {
                self.maintenance.lastError = nil
                self.maintenance.status = "HUD AP ready. Join \(ssid) (password 87654321) in iPhone Wi-Fi Settings, then return and tap Reconnect ADB."
                self.logger.log("HUD MAINT", "Initial ADB probe waiting for manual HUD Wi-Fi join")
            }
            self.firmwareMaintenanceTask = nil
        }
    }

    func reconnectFirmwareMaintenanceADB() {
        guard firmwareMaintenanceActive else { return }
        firmwareMaintenanceTask?.cancel()
        firmwareMaintenanceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.maintenance.connectADB(retries: 4)
            } catch {
                self.maintenance.lastError = error.localizedDescription
                self.maintenance.status = "ADB reconnect failed: \(error.localizedDescription)"
                self.logger.log("HUD MAINT", "Reconnect failed: \(error.localizedDescription)")
            }
            self.firmwareMaintenanceTask = nil
        }
    }

    func exitFirmwareMaintenance() {
        firmwareMaintenanceTask?.cancel()
        firmwareMaintenanceTask = nil
        maintenance.disconnectADB()
        firmwareMaintenanceActive = false
        disableHUDWiFiExposure(reason: "exit firmware maintenance")
        logger.log("HUD MAINT", "Exited maintenance; restoring normal HUD mode and U2W polling")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1800))
            guard let self, self.bluetooth.state == .connected, !self.firmwareMaintenanceActive else { return }
            self.routeGuidance.start(reason: "firmware maintenance ended")
            self.nowPlaying.start(reason: "firmware maintenance ended")
        }
    }

    enum NativeLaneTestPreset: String, CaseIterable, Identifiable {
        case fourStraightUseThird
        case fourStraightUseMiddleTwo
        case fourMixedUseLeftTurn
        case fourMixedUseRightBranch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fourStraightUseThird:
                return "4 straight • use lane 3"
            case .fourStraightUseMiddleTwo:
                return "4 straight • use lanes 2–3"
            case .fourMixedUseLeftTurn:
                return "4 mixed • use straight+left"
            case .fourMixedUseRightBranch:
                return "4 mixed • use straight+right"
            }
        }

        var lanes: [HudCommands.NativeLane] {
            switch self {
            case .fourStraightUseThird:
                return [
                    .init(type: .straight, recommended: false),
                    .init(type: .straight, recommended: false),
                    .init(type: .straight, recommended: true),
                    .init(type: .straight, recommended: false),
                ]
            case .fourStraightUseMiddleTwo:
                return [
                    .init(type: .straight, recommended: false),
                    .init(type: .straight, recommended: true),
                    .init(type: .straight, recommended: true),
                    .init(type: .straight, recommended: false),
                ]
            case .fourMixedUseLeftTurn:
                return [
                    .init(type: .left, recommended: false),
                    .init(type: .straightLeft, recommended: true),
                    .init(type: .straight, recommended: false),
                    .init(type: .right, recommended: false),
                ]
            case .fourMixedUseRightBranch:
                return [
                    .init(type: .left, recommended: false),
                    .init(type: .straight, recommended: false),
                    .init(type: .straightRight, recommended: true),
                    .init(type: .right, recommended: false),
                ]
            }
        }
    }

    func sendNativeLaneTest(_ preset: NativeLaneTestPreset) {
        guard bluetooth.state == .connected else { return }
        bluetooth.enqueue(
            HudCommands.laneGuidance(preset.lanes),
            label: "Native lane test → \(preset.title)"
        )
        logger.log(
            "HUD NATIVE LANES",
            "preset=\(preset.title) values=\(preset.lanes.map { String($0.wireValue) }.joined(separator: ","))"
        )
    }

    func clearNativeLaneTest() {
        clearLaneGuidancePolicy(reason: "native/replay test clear")
        logger.log("HUD NATIVE LANES", "clear")
    }

    func sendRecordedCarPlayLaneReplayStep(_ step: RecordedCarPlayLaneReplay.Step) {
        guard bluetooth.state == .connected else { return }

        // Parked diagnostic replay: send the captured maneuver through the same
        // native HUDWAY path, immediately followed by the captured 0x5204 lane
        // topology normalized to HudLanesManueverCommandPacket values.
        navigation.showCurrentStreet = settings.navigationShowCurrentStreet
        navigation.navigationOn()
        navigation.send(step.instruction)
        setLaneGuidanceForCurrentManeuver(
            step.nativeLanes,
            distanceMeters: step.instruction.distanceMeters,
            context: "Recorded \(step.source) rec \(step.captureRecord) group \(step.laneGroupIndex)"
        )
        logger.log(
            "HUD LANE REPLAY",
            "source=\(step.source) rec=\(step.captureRecord) group=\(step.laneGroupIndex) road=\(step.currentRoad) maneuver=\(step.maneuverDescription) angles=\(step.laneAngleSummary) hud=\(step.hudValueSummary)"
        )
    }

    // MARK: - Persistent stock music renderer experiment

    func startPersistentMusic(mini: Bool) {
        guard bluetooth.state == .connected else {
            persistentMusicStatus = "Connect the HUD over BLE first"
            return
        }
        guard !firmwareMaintenanceActive else {
            persistentMusicStatus = "Exit HUD Firmware Maintenance first"
            return
        }

        persistentMusicTask?.cancel()
        persistentMusicActive = true
        persistentMusicMini = mini
        persistentMusicStatus = mini
            ? "Persistent mini music active • reassert every 5 s"
            : "Persistent full music active • reassert every 5 s"

        musicFilterInitialized = true
        bluetooth.enqueue(
            HudCommands.musicNotificationFilter(enabled: true),
            label: "Persistent music → native filter ON"
        )
        bluetooth.enqueue(
            HudCommands.widgetsMiniState(mini),
            label: "Persistent music → HUD mini state \(mini ? "ON" : "OFF")"
        )
        sendPersistentMusicFrame(reason: "start")

        persistentMusicTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.persistentMusicRefreshInterval)
                guard !Task.isCancelled,
                      self.persistentMusicActive,
                      self.bluetooth.state == .connected,
                      !self.firmwareMaintenanceActive else { break }

                if self.persistentMusicMini {
                    // Keep the stock mini layout selected during this explicit
                    // experiment. This command is global to the stock HUD UI.
                    self.bluetooth.enqueue(
                        HudCommands.widgetsMiniState(true),
                        label: "Persistent music → mini-state reassert"
                    )
                }
                self.sendPersistentMusicFrame(reason: "5 s keepalive")
            }
        }

        logger.log(
            "HUD PERSISTENT MUSIC",
            "started renderer=\(mini ? "mini" : "full") interval=5s stock-timeout=\(settings.notificationExposureSeconds)s"
        )
    }

    func stopPersistentMusic() {
        stopPersistentMusic(sendRestorePackets: true, reason: "manual stop")
    }

    private func stopPersistentMusic(sendRestorePackets: Bool, reason: String) {
        persistentMusicTask?.cancel()
        persistentMusicTask = nil
        let wasActive = persistentMusicActive
        let wasMini = persistentMusicMini
        persistentMusicActive = false
        persistentMusicMini = false
        persistentMusicStatus = "Persistent music stopped"

        if sendRestorePackets, bluetooth.state == .connected {
            if wasMini {
                bluetooth.enqueue(
                    HudCommands.widgetsMiniState(false),
                    label: "Persistent music → restore normal HUD state"
                )
            }
            bluetooth.enqueue(
                HudCommands.musicNotificationFilter(enabled: settings.notifyMusic),
                label: "Persistent music → restore Music filter \(settings.notifyMusic ? "ON" : "OFF")"
            )
            musicFilterInitialized = settings.notifyMusic
        }

        if wasActive {
            logger.log("HUD PERSISTENT MUSIC", "stopped reason=\(reason)")
        }
    }

    private func sendPersistentMusicFrame(reason: String) {
        guard persistentMusicActive, bluetooth.state == .connected else { return }

        let artist = nowPlaying.artist.isEmpty ? "HUDWAY" : nowPlaying.artist
        let track = nowPlaying.title == "No CarPlay media" || nowPlaying.title.isEmpty
            ? "Persistent Music Test"
            : nowPlaying.title

        bluetooth.enqueue(
            HudCommands.musicNotification(artist: artist, track: track),
            label: "Persistent music → \(artist) — \(track)"
        )
        persistentMusicStatus = "\(persistentMusicMini ? "Mini" : "Full") • \(artist) — \(track)"
        logger.log(
            "HUD PERSISTENT MUSIC",
            "reassert reason=\(reason) renderer=\(persistentMusicMini ? "mini" : "full") artist=\(artist) track=\(track)"
        )
    }

    func sendNativeMusicMiniTest(artist: String? = nil, track: String? = nil) {
        guard bluetooth.state == .connected else { return }

        let resolvedArtist = artist ?? (nowPlaying.artist.isEmpty ? "Kenshi Yonezu" : nowPlaying.artist)
        let resolvedTrack = track ?? (nowPlaying.title == "No CarPlay media" ? "Flamingo" : nowPlaying.title)

        // Diagnostic-only firmware-native path. These are BLE commands only:
        // no ADB, filesystem, updater, or firmware writes are involved.
        bluetooth.enqueue(
            HudCommands.musicNotificationFilter(enabled: true),
            label: "Mini music test → native filter ON"
        )
        bluetooth.enqueue(
            HudCommands.widgetsMiniState(true),
            label: "Mini music test → HUD mini state ON"
        )
        bluetooth.enqueue(
            HudCommands.musicNotification(
                artist: resolvedArtist,
                track: resolvedTrack
            ),
            label: "Mini music test → \(resolvedArtist) — \(resolvedTrack)"
        )
        logger.log("HUD MINI MUSIC", "enabled artist=\(resolvedArtist) track=\(resolvedTrack)")
    }

    func restoreFromNativeMusicMiniTest() {
        guard bluetooth.state == .connected else { return }
        bluetooth.enqueue(
            HudCommands.widgetsMiniState(false),
            label: "Mini music test → HUD mini state OFF"
        )
        bluetooth.enqueue(
            HudCommands.musicNotificationFilter(enabled: settings.notifyMusic),
            label: "Mini music test → restore Music filter \(settings.notifyMusic ? "ON" : "OFF")"
        )
        musicFilterInitialized = settings.notifyMusic
        logger.log("HUD MINI MUSIC", "restored normal state")
    }


    func sendNativeMusicTest() {
        pushNowPlayingMetadataToHUD(
            artist: nowPlaying.artist.isEmpty ? "Kenshi Yonezu" : nowPlaying.artist,
            track: nowPlaying.title == "No CarPlay media" ? "Flamingo" : nowPlaying.title
        )
    }


    func pushNowPlayingMetadataToHUD(artist: String? = nil, track: String? = nil) {
        guard bluetooth.state == .connected else { return }

        let resolvedArtist = artist ?? nowPlaying.artist
        let resolvedTrack = track ?? nowPlaying.title
        guard !resolvedArtist.isEmpty,
              !resolvedTrack.isEmpty,
              resolvedTrack != "No CarPlay media" else { return }

        guard settings.notifyMusic else {
            if musicFilterInitialized {
                musicFilterInitialized = false
                bluetooth.enqueue(
                    HudCommands.musicNotificationFilter(enabled: false),
                    label: "Disable native Music notification filter"
                )
            }
            return
        }

        if !musicFilterInitialized {
            musicFilterInitialized = true
            bluetooth.enqueue(
                HudCommands.musicNotificationFilter(enabled: true),
                label: "Enable native Music notification filter"
            )
        }

        bluetooth.enqueue(
            HudCommands.musicNotification(
                artist: resolvedArtist,
                track: resolvedTrack
            ),
            label: "Native music: \(resolvedArtist) — \(resolvedTrack)"
        )

    }


    private func scheduleHUDRehydration(reason: String) {
        hudRehydrateTask?.cancel()
        hudReassertTask?.cancel()

        hudRehydrateTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Phase 1: establish only base transport/session state promptly.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, self.bluetooth.state == .connected else { return }
            self.rehydrateBaseHUD(reason: reason)

            // Phase 2: let the physical HUD firmware finish loading defaults,
            // then overwrite every persisted user-visible setting.
            try? await Task.sleep(for: .milliseconds(1650))
            guard !Task.isCancelled, self.bluetooth.state == .connected else { return }
            self.rehydrateUserHUD(reason: reason)

            // Phase 3: firmware has previously re-applied defaults after our
            // first packets. Reassert display-critical state once more.
            self.hudReassertTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled,
                      self.bluetooth.state == .connected else { return }
                self.reassertDisplayCriticalState(reason: reason)
                self.hudReassertTask = nil
            }

            self.hudRehydrateTask = nil
        }
    }

    private func rehydrateBaseHUD(reason: String) {
        logger.log("HUD REHYDRATE", "PHASE 1 base BEGIN reason=\(reason)")
        bluetooth.enqueue(HudCommands.systemTime(), label: "Rehydrate → system time")
        bluetooth.enqueue(HudCommands.keepAlive(), label: "Rehydrate → keep alive")
        bluetooth.enqueue(HudCommands.phoneName(UIDevice.current.name), label: "Rehydrate → phone name")
        bluetooth.enqueue(HudCommands.fullScreen(true), label: "Rehydrate → full screen")
        bluetooth.enqueue(HudCommands.imperialUnits(), label: "Rehydrate → imperial units (mi/mph)")
        speedEngine.primeRectangularStyle()
        logger.log("HUD REHYDRATE", "PHASE 1 base END")
    }

    private func rehydrateUserHUD(reason: String) {
        logger.log("HUD REHYDRATE", "PHASE 2 persisted state BEGIN")

        bluetooth.enqueue(HudCommands.imperialUnits(), label: "Persisted units → imperial (mi/mph)")
        applyBrightness()
        applyTimeWeather()
        applyColorTheme()
        applyNotificationSettings()
        obd.hudDidBecomeReady()
        restoreDashboardOperatingMode(reason: "phase 2 persisted state / \(reason)")
        ambientLight.rehydrateHUDState()
        speedEngine.primeRectangularStyle()
        speedEngine.rehydrateHUDState()


        musicFilterInitialized = false
        pushNowPlayingMetadataToHUD()

        logger.log(
            "HUD REHYDRATE",
            "PHASE 2 END brightness=\(settings.brightness) autoBrightness=\(settings.autoBrightness) " +
            "timeWeather=\(settings.showTimeWeather) color=\(settings.colorTheme.rawValue) OBDauto=\(obd.autoConnect) " +
            "speedLimit=\(speedEngine.showSpeedLimit) warning=original-auto"
        )
    }

    private func reassertDisplayCriticalState(reason: String) {
        logger.log("HUD REHYDRATE", "PHASE 3 display reassert BEGIN reason=\(reason)")

        // These are deliberately resent after firmware startup so the HUD's
        // own boot defaults cannot win. Rectangular speed-limit style is
        // hard-coded inside the speed engine/command path.
        bluetooth.enqueue(HudCommands.imperialUnits(), label: "Reassert → imperial units (mi/mph)")
        applyBrightness()
        applyColorTheme()
        applyTimeWeather()
        obd.applyWidgetSelection()
        restoreDashboardOperatingMode(reason: "phase 3 display reassert / \(reason)")
        ambientLight.rehydrateHUDState()
        speedEngine.rehydrateHUDState()


        logger.log("HUD REHYDRATE", "PHASE 3 display reassert END")
    }

}