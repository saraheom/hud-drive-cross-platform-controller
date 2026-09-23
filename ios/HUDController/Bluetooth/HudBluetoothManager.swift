import Foundation
import CoreBluetooth
import UIKit
import Observation

@MainActor
@Observable
final class HudBluetoothManager: NSObject {
    enum State: String {
        case idle = "Disconnected"
        case scanning = "Scanning…"
        case connecting = "Connecting…"
        case connected = "Connected"
    }

    struct Device: Identifiable, Hashable {
        let id: UUID
        let name: String
        let rssi: Int
        let peripheral: CBPeripheral

        static func == (lhs: Device, rhs: Device) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private(set) var state: State = .idle
    private(set) var devices: [Device] = []
    private(set) var connectedName: String?
    private(set) var lastRX: String = ""
    private(set) var ancsAuthorized = false
    private(set) var hudAmbientRawValue: Int?
    private(set) var hudAmbientLastUpdated: Date?

    // v90.35.3.11 temporary/passive road-test instrumentation. The HUD already
    // owns the OBD adapter connection; this trace never opens a second OBD BLE
    // connection and never sends OBD requests. It only annotates HUD->iPhone RX
    // frames against the app's simultaneous GPS speed so we can identify any
    // hidden driving-velocity payload that may be exposed by this firmware.
    var obdSpeedTraceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(obdSpeedTraceEnabled, forKey: "HUD.OBD.speedProtocolTraceEnabled")
            obdSpeedTraceStatus = obdSpeedTraceEnabled ? "Armed — passive HUD RX correlation" : "Disabled"
            logger.log("OBD TRACE", obdSpeedTraceEnabled ? "Passive OBD speed protocol trace enabled" : "Passive OBD speed protocol trace disabled")
        }
    }
    private(set) var obdSpeedTraceStatus = "Armed — waiting for speed samples"

    // v90.35.3.12: use the HUD firmware's own diagnostic transport to pull
    // LOG_CATEGORY_OBD after a drive. This does not connect the iPhone to the
    // OBD dongle; it requests the same ZIP the stock HUDWAY bug-report screen
    // downloads from the HUD over this existing BLE link.
    private(set) var obdDiagnosticStatus = "Not requested"
    private(set) var obdDiagnosticLogURL: URL?
    private(set) var obdDiagnosticRawCaptureURL: URL?
    private(set) var obdDiagnosticObservedCategories = "—"
    private(set) var obdDiagnosticTransferActive = false
    private var obdDiagnosticChunks: [Int: Data] = [:]
    private var obdDiagnosticExpectedChunkCount = 0
    private var obdDiagnosticExpectedTotalBytes = 0
    private var obdDiagnosticCategory = ""
    private var obdDiagnosticRequestedCategory = "LOG_CATEGORY_OBD"
    private var obdDiagnosticChunkConflictCount = 0

    // v90.35.3.13.2 OBD forensics. Keep an exact bounded copy of the BLE byte
    // stream while the stock HUD diagnostic transfer is active. This is strictly
    // observational: it does not alter framing, de-duplicate notifications, or
    // reinterpret a non-OBD category as OBD. The capture can therefore be replayed
    // offline if the existing parser rejects a packet.
    private var obdDiagnosticRawBLE = Data()
    private var obdDiagnosticRawCaptureOverflowLogged = false
    private var obdDiagnosticObservedCategorySet = Set<String>()
    private var obdDiagnosticForensicFrameCount = 0
    private var obdDiagnosticMalformedFrameCount = 0
    private struct OBDDiagnosticRecentFragment {
        var data: Data
        var at: Date
    }
    private var obdDiagnosticRecentContinuationFragments: [OBDDiagnosticRecentFragment] = []
    private var obdDiagnosticSuppressedDuplicateFragments = 0
    private var obdDiagnosticSuppressedDuplicateStarts = 0

    // v90.35.3.24.8: diagnostic payloads are much larger than a BLE notification
    // and the HUD can emit ordinary status/UART events between their continuation
    // notifications.  The generic single-stream STX/ETX parser must resynchronize
    // at such a nested STX, which necessarily discards the interrupted diagnostic
    // frame.  Keep a dedicated notification-aware collector for command 5/1/1 and
    // 5/1/4 so an interleaved short event can be parsed normally while the large
    // diagnostic frame resumes with the next continuation notification.
    private var obdDiagnosticWireFrame = Data()
    private var obdDiagnosticWireCollecting = false
    private var obdDiagnosticWireRestartCount = 0
    private var obdDiagnosticInterleavedEventCount = 0
    private var obdDiagnosticReassembledFrameCount = 0
    private let obdDiagnosticWireFrameLimitBytes = 128 * 1024
    private let obdDiagnosticRawCaptureLimitBytes = 8 * 1024 * 1024

    // Short forced logging window around the stock OBD_DRIVING_VELOCITY probe.
    // During this window every HUD RX body is logged with simultaneous GPS speed,
    // rather than applying the normal passive-trace rate limiting.
    private var obdSpeedProbeForensicsUntil = Date.distantPast
    private var obdSpeedProbeForensicsLabel = ""
    private var obdSpeedProbeForensicsFrameCount = 0
    private struct OBDSpeedProbeScore {
        var hits = 0
        var distinctReferenceSpeeds = Set<Int>()
        var lastValue = 0
    }
    private var obdSpeedProbeScores: [String: OBDSpeedProbeScore] = [:]

    // v90.35.3.24.6.1: deeper OBD speed probe. Unlike v2, this keeps a bounded
    // in-memory sample set and performs regression against GPS only after the
    // road window ends. It therefore does not flood the HUD log with every BLE
    // frame while MainVideo is being stress-tested. The probe remains strictly
    // on the existing HUD BLE link; it never opens a second OBD connection and
    // never sends raw ELM/PID commands.
    private(set) var obdDeepSpeedProbeActive = false
    private(set) var obdDeepSpeedProbeStatus = "Not run"
    private(set) var obdDeepSpeedProbeReportURL: URL?
    private var obdDeepSpeedProbeUntil = Date.distantPast
    private var obdDeepSpeedProbeLabel = ""
    private var obdDeepSpeedSamples: [OBDDeepSpeedSample] = []
    private var obdDeepGPSPoints: [OBDDeepGPSPoint] = []
    private var obdDeepDroppedSamples = 0
    private let obdDeepSpeedSampleCap = 12_000

    var onOBDConnectionEvent: ((Bool, String) -> Void)?
    var onWiFiSTAStatusEvent: ((Int, String, String) -> Void)?
    var onTransportReady: (() -> Void)?
    var onTransportDisconnected: (() -> Void)?
    var onHUDSessionReset: (() -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var txQueue: [(Data, String)] = []
    private var currentChunks: [Data] = []
    private var currentLabel = ""
    private var writing = false
    private var rxBuffer = Data()

    private var obdTraceReferenceSpeedMph = 0
    private var obdTraceConnected = false
    private var obdTraceLastHeartbeatAt = Date.distantPast
    private var obdTraceLastFrameSignatureByKey: [String: String] = [:]
    private var obdTraceLastFrameAtByKey: [String: Date] = [:]

    private let savedPeripheralIDKey = "HUD.savedPeripheralIdentifier"
    private let savedPeripheralNameKey = "HUD.savedPeripheralName"
    private var attemptedSavedReconnect = false

    // App-level reconnect watchdog. We intentionally keep CoreBluetooth
    // connection options=nil because that is the known-good physical-device path.
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var userRequestedDisconnect = false
    private var autoReconnectEnabled = true
    private var lastHUDSessionHelloAt = Date.distantPast

    var savedHUDName: String? {
        UserDefaults.standard.string(forKey: savedPeripheralNameKey)
    }

    var reconnectStatus: String {
        if userRequestedDisconnect { return "Paused by user" }
        if reconnectTask != nil { return "Retrying automatically" }
        return autoReconnectEnabled ? "Enabled" : "Disabled"
    }

    var userDisconnectRequested: Bool { userRequestedDisconnect }

    let logger: LogManager

    init(logger: LogManager) {
        self.logger = logger
        let defaults = UserDefaults.standard
        self.obdSpeedTraceEnabled = defaults.object(forKey: "HUD.OBD.speedProtocolTraceEnabled") == nil
            ? true
            : defaults.bool(forKey: "HUD.OBD.speedProtocolTraceEnabled")
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "HUDControllerCentral"
        ])
    }

    private func saveConnectedHUD(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(
            peripheral.identifier.uuidString,
            forKey: savedPeripheralIDKey
        )
        UserDefaults.standard.set(
            peripheral.name ?? "HUD Drive",
            forKey: savedPeripheralNameKey
        )
        logger.log(
            "BLE MEMORY",
            "Saved HUD \(peripheral.name ?? "HUD Drive") | \(peripheral.identifier)"
        )
        reconnectAttempt = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        userRequestedDisconnect = false
        autoReconnectEnabled = true
    }

    func forgetSavedHUD() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        autoReconnectEnabled = false
        userRequestedDisconnect = true
        UserDefaults.standard.removeObject(forKey: savedPeripheralIDKey)
        UserDefaults.standard.removeObject(forKey: savedPeripheralNameKey)
        logger.log("BLE MEMORY", "Forgot saved HUD and stopped auto-reconnect")
    }

    func reconnectSavedHUD() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempt = 0
        userRequestedDisconnect = false
        autoReconnectEnabled = true
        attemptedSavedReconnect = false
        reconnectSavedHUDIfPossible()
    }

    private func reconnectSavedHUDIfPossible() {
        guard central.state == .poweredOn else {
            logger.log("BLE AUTO", "Reconnect deferred: Bluetooth is not powered on")
            return
        }
        guard autoReconnectEnabled, !userRequestedDisconnect else {
            logger.log("BLE AUTO", "Reconnect skipped: disabled or user-requested disconnect")
            return
        }
        guard state != .connected && state != .connecting else { return }

        guard let raw = UserDefaults.standard.string(forKey: savedPeripheralIDKey),
              let uuid = UUID(uuidString: raw) else {
            logger.log("BLE AUTO", "No previously saved HUD")
            return
        }

        logger.log("BLE AUTO", "Looking for saved HUD \(raw)")
        let retrieved = central.retrievePeripherals(withIdentifiers: [uuid])

        guard let saved = retrieved.first else {
            logger.log("BLE AUTO", "Saved HUD is not currently retrievable")
            scheduleReconnect(reason: "saved peripheral not retrievable")
            return
        }

        let name = saved.name
            ?? UserDefaults.standard.string(forKey: savedPeripheralNameKey)
            ?? "HUD Drive"

        logger.log(
            "BLE AUTO",
            "Retrieved \(name); auto-connect attempt \(reconnectAttempt + 1) using options=nil"
        )

        peripheral = saved
        saved.delegate = self
        state = .connecting
        central.connect(saved, options: nil)
    }

    private func scheduleReconnect(reason: String) {
        guard autoReconnectEnabled, !userRequestedDisconnect else { return }
        guard reconnectTask == nil else { return }
        guard central.state == .poweredOn else { return }

        // 1s, 2s, 4s, 8s, 15s, then 30s thereafter.
        let delays: [Double] = [1, 2, 4, 8, 15, 30]
        let delay = delays[min(reconnectAttempt, delays.count - 1)]
        reconnectAttempt += 1

        logger.log(
            "BLE AUTO",
            "Scheduling reconnect in \(Int(delay))s (reason: \(reason), attempt \(reconnectAttempt))"
        )

        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            self.reconnectSavedHUDIfPossible()
        }
    }

    private func cancelReconnect(reason: String) {
        if reconnectTask != nil {
            logger.log("BLE AUTO", "Cancelled pending reconnect: \(reason)")
        }
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    func scan() {
        userRequestedDisconnect = false
        autoReconnectEnabled = true
        cancelReconnect(reason: "manual scan")
        guard central.state == .poweredOn else {
            logger.log("BLE", "Cannot scan: Bluetooth state \(central.state.rawValue)")
            return
        }
        devices.removeAll()
        state = .scanning
        logger.log("BLE", "Scanning for all BLE advertisers (HUD is name-prioritized; NUS verified after connection)")
        // Do not filter by the Nordic UART service at discovery time.
        // HUD Drive does not reliably include the NUS UUID in its advertising
        // packet. Windows testing showed that it can advertise only its local
        // name, then expose NUS after GATT connection.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        Task {
            try? await Task.sleep(for: .seconds(8))
            await MainActor.run {
                self.central.stopScan()
                if self.state == .scanning { self.state = .idle }
                self.logger.log("BLE", "Scan complete: \(self.devices.count) named BLE device(s) shown in picker")
                if self.devices.isEmpty {
                    self.logger.log("BLE", "No named devices discovered. Check Bluetooth permission and that HUD is powered/not connected to another phone.")
                }
            }
        }
    }

    func connect(_ device: Device) {
        cancelReconnect(reason: "manual connect")
        reconnectAttempt = 0
        userRequestedDisconnect = false
        autoReconnectEnabled = true
        central.stopScan()
        state = .connecting
        peripheral = device.peripheral
        peripheral?.delegate = self
        logger.log("BLE", "Connecting to \(device.name) with baseline CoreBluetooth options=nil")
        logger.log("ANCS", "Pre-connect ANCS authorization state = \(device.peripheral.ancsAuthorized)")
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        logger.log("BLE", "User requested disconnect; automatic reconnect paused")
        userRequestedDisconnect = true
        autoReconnectEnabled = false
        cancelReconnect(reason: "user requested disconnect")
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func initializeHUD() {
        enqueue(HudCommands.systemTime(), label: "System time")
        enqueue(HudCommands.keepAlive(), label: "KeepAlive")
        enqueue(HudCommands.phoneName(UIDevice.current.name), label: "Phone name")
        enqueue(HudCommands.keepAlive(), label: "KeepAlive")
        enqueue(HudCommands.fullScreen(true), label: "Full screen")
        enqueue(HudCommands.navigationState(false), label: "Navigation OFF")
        enqueue(HudCommands.manualBrightness(50), label: "Brightness defaults")
        enqueue(HudCommands.keepAlive(), label: "KeepAlive")
    }

    func enqueue(_ packet: Data, label: String) {
        guard state == .connected else {
            logger.log("ERROR", "Cannot send \(label): not connected")
            return
        }
        txQueue.append((packet, label))
        pumpTX()
    }

    private func pumpTX() {
        guard !writing,
              currentChunks.isEmpty,
              !txQueue.isEmpty,
              let peripheral,
              let txCharacteristic else { return }

        let next = txQueue.removeFirst()
        currentLabel = next.1
        currentChunks = HudProtocol.chunks(next.0)
        logger.log("TX", "\(next.1): \(HudProtocol.hex(next.0))")
        writing = true
        writeNextChunk(peripheral: peripheral, characteristic: txCharacteristic)
    }

    private func writeNextChunk(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard !currentChunks.isEmpty else {
            writing = false
            currentLabel = ""
            pumpTX()
            return
        }

        guard peripheral.canSendWriteWithoutResponse else {
            // CoreBluetooth will call peripheralIsReady(toSendWriteWithoutResponse:)
            return
        }

        let chunk = currentChunks.removeFirst()
        logger.log("TX CHUNK", HudProtocol.hex(chunk))
        peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)

        // One chunk at a time; next chunk is released asynchronously to avoid
        // splicing packets on devices that consume NUS writes slowly.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            self.writeNextChunk(peripheral: peripheral, characteristic: characteristic)
        }
    }

    private func readJavaUTF(_ body: Data, index: inout Int) -> String? {
        guard body.count >= index + 2 else { return nil }
        let length = Int(body[index]) << 8 | Int(body[index + 1])
        index += 2
        guard body.count >= index + length else { return nil }
        let data = body.subdata(in: index..<(index + length))
        index += length
        // STA reason/address strings observed in this protocol are ASCII/UTF-8.
        // javaWriteUTF differs only for NUL/non-ASCII edge cases, which do not
        // apply to IPv4 addresses and firmware reason strings.
        return String(data: data, encoding: .utf8) ?? ""
    }


    func requestOBDDiagnosticLogs(maxLastFilesCount: Int32 = 2) {
        guard state == .connected else {
            obdDiagnosticStatus = "HUD BLE disconnected"
            return
        }
        if obdDiagnosticTransferActive, !obdDiagnosticRawBLE.isEmpty {
            saveOBDDiagnosticRawCapture(reason: "new request replaced previous capture")
        }
        obdDiagnosticChunks.removeAll(keepingCapacity: true)
        obdDiagnosticExpectedChunkCount = 0
        obdDiagnosticExpectedTotalBytes = 0
        obdDiagnosticRequestedCategory = "LOG_CATEGORY_OBD"
        obdDiagnosticCategory = ""
        obdDiagnosticChunkConflictCount = 0
        obdDiagnosticLogURL = nil
        obdDiagnosticRawCaptureURL = nil
        obdDiagnosticRawBLE.removeAll(keepingCapacity: true)
        obdDiagnosticRawCaptureOverflowLogged = false
        obdDiagnosticObservedCategorySet.removeAll(keepingCapacity: true)
        obdDiagnosticObservedCategories = "—"
        obdDiagnosticForensicFrameCount = 0
        obdDiagnosticMalformedFrameCount = 0
        obdDiagnosticSuppressedDuplicateFragments = 0
        obdDiagnosticWireFrame.removeAll(keepingCapacity: true)
        obdDiagnosticWireCollecting = false
        obdDiagnosticWireRestartCount = 0
        obdDiagnosticInterleavedEventCount = 0
        obdDiagnosticReassembledFrameCount = 0
        obdDiagnosticRecentContinuationFragments.removeAll(keepingCapacity: true)
        obdDiagnosticSuppressedDuplicateStarts = 0
        obdDiagnosticTransferActive = true
        obdDiagnosticStatus = "Requesting HUD OBD diagnostic ZIP + raw capture…"
        logger.log("OBD HUD LOG", "Request LOG_CATEGORY_OBD maxLastFilesCount=\(maxLastFilesCount)")
        logger.log("OBD HUD RAW", "BEGIN requested=LOG_CATEGORY_OBD capBytes=\(obdDiagnosticRawCaptureLimitBytes) gps=\(obdTraceReferenceSpeedMph)mph")
        enqueue(
            HudCommands.requestOBDDiagnosticLogs(maxLastFilesCount: maxLastFilesCount),
            label: "Request HUD OBD diagnostic logs"
        )
    }

    func cancelOBDDiagnosticLogs() {
        if state == .connected {
            enqueue(HudCommands.cancelDiagnosticLogTransfer(), label: "Cancel HUD diagnostic log transfer")
        }
        saveOBDDiagnosticRawCapture(reason: "user stopped transfer")
        obdDiagnosticTransferActive = false
        obdDiagnosticWireFrame.removeAll(keepingCapacity: true)
        obdDiagnosticWireCollecting = false
        obdDiagnosticStatus = obdDiagnosticRawCaptureURL == nil
            ? "Transfer stopped"
            : "Transfer stopped • raw capture ready"
        logger.log("OBD HUD LOG", "Transfer stopped by user; raw capture saved if any bytes were received")
    }

    private func captureOBDDiagnosticRawBLE(_ data: Data) {
        guard obdDiagnosticTransferActive, !data.isEmpty else { return }
        let remaining = obdDiagnosticRawCaptureLimitBytes - obdDiagnosticRawBLE.count
        if remaining > 0 {
            obdDiagnosticRawBLE.append(contentsOf: data.prefix(remaining))
        }
        if data.count > remaining, !obdDiagnosticRawCaptureOverflowLogged {
            obdDiagnosticRawCaptureOverflowLogged = true
            logger.log(
                "OBD HUD RAW",
                "Raw BLE capture reached \(obdDiagnosticRawCaptureLimitBytes) byte safety cap; logging continues but binary capture is truncated"
            )
        }
    }

    private func shouldSuppressDuplicateDiagnosticBLEFragment(_ data: Data) -> Bool {
        guard obdDiagnosticTransferActive, !data.isEmpty else { return false }

        // A diagnostic packet's *first* BLE notification is intentionally almost
        // identical for every archive chunk (STX + 05/01/01 + Java UTF category).
        // v4 treated identical starts inside a 200 ms window as duplicate BLE
        // delivery, which can silently discard the start of the next real chunk and
        // splice its continuation bytes onto the previous packet. Never de-duplicate
        // an STX-bearing notification here. consumeDiagnosticBLEFragment() can safely
        // identify a duplicate start only while the same packet is still incomplete.
        if data.first == HudProtocol.stx { return false }

        // Field captures also contain true duplicate *continuation* notifications,
        // sometimes interleaved A/B/A/B rather than adjacent. De-duplicate only
        // within the current diagnostic wire frame and only in a short time window.
        // The history is cleared at every authoritative diagnostic STX, so an equal
        // compressed block in a later archive chunk is never suppressed.
        let now = Date()
        let duplicateWindow: TimeInterval = 0.15
        obdDiagnosticRecentContinuationFragments.removeAll {
            now.timeIntervalSince($0.at) > duplicateWindow
        }
        if obdDiagnosticRecentContinuationFragments.contains(where: { $0.data == data }) {
            obdDiagnosticSuppressedDuplicateFragments += 1
            if obdDiagnosticSuppressedDuplicateFragments == 1 || obdDiagnosticSuppressedDuplicateFragments % 50 == 0 {
                logger.log(
                    "OBD HUD RAW",
                    "Suppressed duplicate continuation within current diagnostic frame count=\(obdDiagnosticSuppressedDuplicateFragments) bytes=\(data.count); raw capture still retains every notification"
                )
            }
            return true
        }
        obdDiagnosticRecentContinuationFragments.append(OBDDiagnosticRecentFragment(data: data, at: now))
        if obdDiagnosticRecentContinuationFragments.count > 24 {
            obdDiagnosticRecentContinuationFragments.removeFirst(obdDiagnosticRecentContinuationFragments.count - 24)
        }
        return false
    }

    private func isDiagnosticStartNotification(_ data: Data) -> Bool {
        guard data.count >= 4, data[0] == HudProtocol.stx else { return false }
        // Command/p1/p2 are 05/01/01 for a ZIP chunk and 05/01/04 for the
        // remaining-log bitmap; none of these bytes require wire escaping.
        return data[1] == 5 && data[2] == 1 && (data[3] == 1 || data[3] == 4)
    }

    /// Consume one raw CoreBluetooth notification for the large diagnostic
    /// transport. Returns true when this notification belongs to the diagnostic
    /// frame and therefore must not be appended to the generic rxBuffer.
    private func consumeDiagnosticBLEFragment(_ data: Data) -> Bool {
        guard obdDiagnosticTransferActive, !data.isEmpty else { return false }

        if data.first == HudProtocol.stx {
            if isDiagnosticStartNotification(data) {
                if obdDiagnosticWireCollecting, !obdDiagnosticWireFrame.isEmpty {
                    // A fresh diagnostic STX is authoritative. Every archive chunk
                    // begins with an almost identical category/header prefix, so the
                    // prefix itself cannot distinguish a retransmitted start from the
                    // next real chunk. Restarting here is lossless for a true duplicate
                    // and prevents a missing/incomplete prior chunk from consuming the
                    // next chunk's continuation bytes. Missing chunks are recovered by
                    // the indexed archive reassembler rather than by splicing frames.
                    obdDiagnosticWireRestartCount += 1
                    logger.log(
                        "OBD HUD REASM",
                        "Fresh diagnostic STX replaced incomplete frame bytes=\(obdDiagnosticWireFrame.count) restarts=\(obdDiagnosticWireRestartCount)"
                    )
                }
                obdDiagnosticWireFrame = data
                obdDiagnosticWireCollecting = true
                obdDiagnosticRecentContinuationFragments.removeAll(keepingCapacity: true)
            } else if obdDiagnosticWireCollecting {
                // A normal HUD event is interleaved between continuation
                // notifications. Leave the diagnostic accumulator untouched and
                // let the ordinary protocol parser handle this complete event.
                obdDiagnosticInterleavedEventCount += 1
                if obdDiagnosticInterleavedEventCount == 1 || obdDiagnosticInterleavedEventCount % 50 == 0 {
                    logger.log(
                        "OBD HUD REASM",
                        "Interleaved HUD event preserved while diagnostic frame waits count=\(obdDiagnosticInterleavedEventCount) head=\(HudProtocol.hex(data.prefix(24)))"
                    )
                }
                return false
            } else {
                return false
            }
        } else {
            guard obdDiagnosticWireCollecting else { return false }
            obdDiagnosticWireFrame.append(data)
        }

        guard obdDiagnosticWireFrame.count <= obdDiagnosticWireFrameLimitBytes else {
            obdDiagnosticMalformedFrameCount += 1
            logger.log(
                "OBD HUD REASM",
                "Abandon oversized diagnostic wire frame bytes=\(obdDiagnosticWireFrame.count) cap=\(obdDiagnosticWireFrameLimitBytes)"
            )
            obdDiagnosticWireFrame.removeAll(keepingCapacity: true)
            obdDiagnosticWireCollecting = false
            obdDiagnosticRecentContinuationFragments.removeAll(keepingCapacity: true)
            return true
        }

        // Literal ETX bytes inside the body are escaped as 7D 7E, so the first
        // raw 0x03 is an authoritative end of this diagnostic wire frame.
        guard let etxIndex = obdDiagnosticWireFrame.firstIndex(of: HudProtocol.etx) else {
            return true
        }

        let endExclusive = obdDiagnosticWireFrame.index(after: etxIndex)
        let frame = obdDiagnosticWireFrame.subdata(in: obdDiagnosticWireFrame.startIndex..<endExclusive)
        let trailing = obdDiagnosticWireFrame.distance(from: endExclusive, to: obdDiagnosticWireFrame.endIndex)
        obdDiagnosticWireFrame.removeAll(keepingCapacity: true)
        obdDiagnosticWireCollecting = false
        obdDiagnosticRecentContinuationFragments.removeAll(keepingCapacity: true)

        if trailing > 0 {
            // We have not observed packed multiple frames in one HUD notification;
            // log rather than guessing how to splice trailing bytes into rxBuffer.
            logger.log("OBD HUD REASM", "Diagnostic frame had \(trailing) trailing wire bytes after ETX; ignored for diagnostic assembly")
        }

        guard let body = HudProtocol.unescape(frame), body.count >= 3,
              body[0] == 5, body[1] == 1 else {
            obdDiagnosticMalformedFrameCount += 1
            logger.log("OBD HUD REASM", "Completed wire frame failed diagnostic unescape bytes=\(frame.count)")
            return true
        }

        obdDiagnosticReassembledFrameCount += 1
        if obdDiagnosticReassembledFrameCount <= 3 || obdDiagnosticReassembledFrameCount % 100 == 0 {
            logger.log(
                "OBD HUD REASM",
                "Completed diagnostic frame #\(obdDiagnosticReassembledFrameCount) wireBytes=\(frame.count) bodyBytes=\(body.count) interleaved=\(obdDiagnosticInterleavedEventCount) restarts=\(obdDiagnosticWireRestartCount)"
            )
        }
        logDiagnosticFrameForensics(frame, body: body)
        _ = handleDiagnosticPacket(body)
        return true
    }

    private func isPlausibleDiagnosticCategory(_ category: String) -> Bool {
        guard category.hasPrefix("LOG_CATEGORY_"), category.count <= 64 else { return false }
        return category.unicodeScalars.allSatisfy { scalar in
            scalar.value == 0x5F ||
            (0x30...0x39).contains(scalar.value) ||
            (0x41...0x5A).contains(scalar.value)
        }
    }

    private func saveOBDDiagnosticRawCapture(reason: String) {
        guard !obdDiagnosticRawBLE.isEmpty else {
            logger.log("OBD HUD RAW", "No raw BLE bytes to save reason=\(reason)")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "HUD_OBD_RawBLE_\(formatter.string(from: Date())).bin"
        do {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let url = base.appendingPathComponent(filename)
            try obdDiagnosticRawBLE.write(to: url, options: .atomic)
            obdDiagnosticRawCaptureURL = url
            logger.log(
                "OBD HUD RAW",
                "Saved \(url.lastPathComponent) bytes=\(obdDiagnosticRawBLE.count) frames=\(obdDiagnosticForensicFrameCount) malformed=\(obdDiagnosticMalformedFrameCount) dupContinuation=\(obdDiagnosticSuppressedDuplicateFragments) dupStart=\(obdDiagnosticSuppressedDuplicateStarts) categories=\(obdDiagnosticObservedCategories) reason=\(reason)"
            )
        } catch {
            logger.log("OBD HUD RAW", "Raw capture save failed: \(error.localizedDescription)")
        }
    }

    func requestRemainingDiagnosticLogTypes() {
        guard state == .connected else {
            obdDiagnosticStatus = "HUD BLE disconnected"
            return
        }
        enqueue(HudCommands.requestRemainingDiagnosticLogs(), label: "Request remaining HUD diagnostic log types")
        logger.log("OBD HUD LOG", "Requested remaining-log bitmap")
    }

    private func int32BE(_ data: Data, index: inout Int) -> Int? {
        guard data.count >= index + 4 else { return nil }
        let value = (Int(data[index]) << 24) | (Int(data[index + 1]) << 16) |
            (Int(data[index + 2]) << 8) | Int(data[index + 3])
        index += 4
        return value
    }

    private func recordObservedDiagnosticCategory(_ category: String) {
        guard !category.isEmpty else { return }
        obdDiagnosticObservedCategorySet.insert(category)
        obdDiagnosticObservedCategories = obdDiagnosticObservedCategorySet.sorted().joined(separator: ", ")
    }

    private func obdDiagnosticSignatureHits(_ payload: Data) -> [String] {
        guard !payload.isEmpty else { return [] }
        let bytes = [UInt8](payload)
        var hits: [String] = []

        func add(_ value: String) {
            if !hits.contains(value) { hits.append(value) }
        }
        if bytes.count >= 2 {
            for i in 0..<(bytes.count - 1) {
                if bytes[i] == 0x41, bytes[i + 1] == 0x0D { add("41 0D@\(i)") }
                if bytes[i] == 0x01, bytes[i + 1] == 0x0D { add("01 0D@\(i)") }
            }
        }
        if bytes.count >= 4 {
            for i in 0...(bytes.count - 4) where bytes[i] == 0x50 && bytes[i + 1] == 0x4B {
                add("ZIP/PK@\(i)")
            }
        }
        let upperASCII = String(decoding: payload, as: UTF8.self).uppercased()
        for token in ["010D", "410D", "ELM327", "ELM", "ATZ", "ATE0", "ATI", "OBDII", "OBD-II"] {
            if upperASCII.contains(token) { add("ascii:\(token)") }
        }
        let speedCandidates = obdTraceScalarCandidates(payload: payload)
        for candidate in speedCandidates.prefix(8) { add("speed:\(candidate)") }
        return hits
    }

    private func logDiagnosticFrameForensics(_ frame: Data, body: Data) {
        guard obdDiagnosticTransferActive, body.count >= 3 else { return }
        obdDiagnosticForensicFrameCount += 1
        let command = Int(body[0])
        let p1 = Int(body[1])
        let p2 = Int(body[2])
        let kmh = Int((Double(obdTraceReferenceSpeedMph) * 1.609344).rounded())

        if command == 5, p1 == 1, p2 == 1 {
            var index = 3
            let category = readJavaUTF(body, index: &index)
            let totalSize = category == nil ? nil : int32BE(body, index: &index)
            let allChunks = totalSize == nil ? nil : int32BE(body, index: &index)
            let chunkIndex = allChunks == nil ? nil : int32BE(body, index: &index)
            let chunkSize = chunkIndex == nil ? nil : int32BE(body, index: &index)
            let available = max(0, body.count - index)
            if let category { recordObservedDiagnosticCategory(category) }
            let scanPayload = index < body.count ? body.subdata(in: index..<body.count) : Data()
            let hits = obdDiagnosticSignatureHits(scanPayload)
            let categoryText = category ?? "<unreadable>"
            let totalText = totalSize.map { String($0) } ?? "?"
            let chunksText = allChunks.map { String($0) } ?? "?"
            let indexText = chunkIndex.map { String($0 + 1) } ?? "?"
            let declaredText = chunkSize.map { String($0) } ?? "?"
            let shouldLogFrame = obdDiagnosticForensicFrameCount <= 5 ||
                obdDiagnosticForensicFrameCount % 50 == 0 || !hits.isEmpty
            if shouldLogFrame {
                logger.log(
                    "OBD HUD RAW",
                    "event#\(obdDiagnosticForensicFrameCount) category=\(categoryText) requested=\(obdDiagnosticRequestedCategory) total=\(totalText) chunk=\(indexText)/\(chunksText) declared=\(declaredText) available=\(available) wireBytes=\(frame.count) bodyBytes=\(body.count) gps=\(obdTraceReferenceSpeedMph)mph/\(kmh)kmh hits=[\(hits.joined(separator: ","))]"
                )
            }
            if let category, category != obdDiagnosticRequestedCategory,
               (obdDiagnosticForensicFrameCount <= 5 || obdDiagnosticForensicFrameCount % 100 == 0) {
                logger.log("OBD HUD RAW", "CATEGORY MISMATCH requested=\(obdDiagnosticRequestedCategory) received=\(category)")
            }
        } else {
            let payload = body.count > 3 ? body.subdata(in: 3..<body.count) : Data()
            let hits = obdDiagnosticSignatureHits(payload)
            logger.log(
                "OBD HUD RAW",
                "event#\(obdDiagnosticForensicFrameCount) hdr=\(command)/\(p1)/\(p2) wireBytes=\(frame.count) bodyBytes=\(body.count) gps=\(obdTraceReferenceSpeedMph)mph/\(kmh)kmh hits=[\(hits.joined(separator: ","))] body=\(HudProtocol.hex(body.prefix(96)))"
            )
        }
    }

    func beginOBDSpeedProbeForensics(duration: TimeInterval = 14.0, label: String) {
        obdSpeedProbeForensicsUntil = Date().addingTimeInterval(max(1.0, duration))
        obdSpeedProbeForensicsLabel = label
        obdSpeedProbeForensicsFrameCount = 0
        obdSpeedProbeScores.removeAll(keepingCapacity: true)
        logger.log(
            "OBD PROBE FORENSICS",
            "BEGIN label=\(label) duration=\(String(format: "%.1f", duration))s gps=\(obdTraceReferenceSpeedMph)mph"
        )
    }

    func endOBDSpeedProbeForensics(reason: String) {
        guard obdSpeedProbeForensicsUntil > .distantPast else { return }
        let ranked = obdSpeedProbeScores
            .sorted {
                if $0.value.distinctReferenceSpeeds.count != $1.value.distinctReferenceSpeeds.count {
                    return $0.value.distinctReferenceSpeeds.count > $1.value.distinctReferenceSpeeds.count
                }
                return $0.value.hits > $1.value.hits
            }
            .prefix(10)
            .map { key, value in
                "\(key){hits=\(value.hits),distinctGPS=\(value.distinctReferenceSpeeds.count),last=\(value.lastValue)}"
            }
            .joined(separator: ";")
        logger.log(
            "OBD PROBE SUMMARY",
            "label=\(obdSpeedProbeForensicsLabel) frames=\(obdSpeedProbeForensicsFrameCount) reason=\(reason) top=[\(ranked.isEmpty ? "none" : ranked)]"
        )
        obdSpeedProbeForensicsUntil = .distantPast
        obdSpeedProbeForensicsLabel = ""
    }

    func beginOBDDeepSpeedProbe(duration: TimeInterval = 92.0, label: String) {
        obdDeepSpeedProbeActive = true
        obdDeepSpeedProbeUntil = Date().addingTimeInterval(max(5.0, duration))
        obdDeepSpeedProbeLabel = label
        obdDeepSpeedSamples.removeAll(keepingCapacity: true)
        obdDeepGPSPoints.removeAll(keepingCapacity: true)
        obdDeepDroppedSamples = 0
        obdDeepSpeedProbeReportURL = nil
        obdDeepGPSPoints.append(OBDDeepGPSPoint(
            time: Date().timeIntervalSinceReferenceDate,
            mph: obdTraceReferenceSpeedMph
        ))
        obdDeepSpeedProbeStatus = "Running • collecting HUD RX + GPS"
        logger.log(
            "OBD SPEED V3",
            "BEGIN duration=\(String(format: "%.0f", duration))s label={\(label)} sampleCap=\(obdDeepSpeedSampleCap); no direct OBD connection / no raw PID request"
        )
    }

    func endOBDDeepSpeedProbe(reason: String) {
        guard obdDeepSpeedProbeActive || !obdDeepSpeedSamples.isEmpty else { return }
        obdDeepSpeedProbeActive = false
        obdDeepSpeedProbeUntil = .distantPast

        let samples = obdDeepSpeedSamples
        let gps = obdDeepGPSPoints
        let candidates = OBDDeepSpeedAnalyzer.analyze(samples: samples, gps: gps)
        let pidHits = OBDDeepSpeedAnalyzer.directPIDHits(samples: samples, gps: gps)
        let top = candidates.prefix(12).map(\.summary).joined(separator: "; ")
        let gpsSpeeds = gps.map(\.mph)
        let gpsMin = gpsSpeeds.min() ?? 0
        let gpsMax = gpsSpeeds.max() ?? 0

        logger.log(
            "OBD DEEP SUMMARY",
            "label={\(obdDeepSpeedProbeLabel)} reason={\(reason)} frames=\(samples.count) dropped=\(obdDeepDroppedSamples) gpsSamples=\(gps.count) gpsRange=\(gpsMin)-\(gpsMax)mph direct410D=\(pidHits.count) top=[\(top.isEmpty ? "none" : top)]"
        )
        for candidate in candidates.prefix(12) {
            logger.log("OBD DEEP CANDIDATE", candidate.summary)
        }
        for hit in pidHits.prefix(20) {
            logger.log("OBD DEEP PID410D", hit.summary)
        }

        let report = OBDDeepSpeedAnalyzer.report(
            label: obdDeepSpeedProbeLabel,
            reason: reason,
            samples: samples,
            gps: gps,
            candidates: candidates,
            pidHits: pidHits
        )
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "HUD_OBD_SpeedProbeV3_\(formatter.string(from: Date())).txt"
        do {
            let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let url = base.appendingPathComponent(filename)
            try report.write(to: url, atomically: true, encoding: .utf8)
            obdDeepSpeedProbeReportURL = url
            obdDeepSpeedProbeStatus = candidates.isEmpty
                ? "Complete • no strong HUD RX speed field • report saved"
                : "Complete • \(candidates.count) correlated candidate(s) • report saved"
            logger.log("OBD SPEED V3", "REPORT saved=\(url.lastPathComponent) bytes=\(report.utf8.count)")
        } catch {
            obdDeepSpeedProbeStatus = candidates.isEmpty
                ? "Complete • no strong candidate • report save failed"
                : "Complete • candidates found • report save failed"
            logger.log("OBD SPEED V3", "REPORT save failed error=\(error.localizedDescription)")
        }

        obdDeepSpeedSamples.removeAll(keepingCapacity: false)
        obdDeepGPSPoints.removeAll(keepingCapacity: false)
        obdDeepSpeedProbeLabel = ""
    }

    private func recordOBDDeepSpeedProbeFrame(_ body: Data) {
        guard obdDeepSpeedProbeActive else { return }
        if Date() > obdDeepSpeedProbeUntil {
            endOBDDeepSpeedProbe(reason: "probe deadline reached")
            return
        }
        guard body.count >= 3 else { return }
        guard obdDeepSpeedSamples.count < obdDeepSpeedSampleCap else {
            obdDeepDroppedSamples += 1
            return
        }
        // Keep enough payload for unknown speed encodings while bounding memory.
        let payload = body.count > 3 ? body.subdata(in: 3..<min(body.count, 67)) : Data()
        obdDeepSpeedSamples.append(OBDDeepSpeedSample(
            time: Date().timeIntervalSinceReferenceDate,
            command: Int(body[0]),
            p1: Int(body[1]),
            p2: Int(body[2]),
            payload: payload
        ))
    }

    private func logOBDSpeedProbeForensics(_ body: Data) {
        guard Date() <= obdSpeedProbeForensicsUntil, body.count >= 3 else { return }
        obdSpeedProbeForensicsFrameCount += 1
        let command = Int(body[0])
        let p1 = Int(body[1])
        let p2 = Int(body[2])
        let payload = body.count > 3 ? body.subdata(in: 3..<body.count) : Data()
        let kmh = Int((Double(obdTraceReferenceSpeedMph) * 1.609344).rounded())
        let candidates = obdTraceScalarCandidates(payload: payload)
        scoreOBDSpeedProbeCandidates(command: command, p1: p1, p2: p2, payload: payload)
        let signatures = obdDiagnosticSignatureHits(payload)
        logger.log(
            "OBD PROBE RX",
            "label=\(obdSpeedProbeForensicsLabel) seq=\(obdSpeedProbeForensicsFrameCount) hdr=\(command)/\(p1)/\(p2) bodyBytes=\(body.count) gps=\(obdTraceReferenceSpeedMph)mph/\(kmh)kmh candidates=[\(candidates.joined(separator: ","))] signatures=[\(signatures.joined(separator: ","))] body=\(HudProtocol.hex(body.prefix(128)))"
        )
    }

    private func scoreOBDSpeedProbeCandidates(command: Int, p1: Int, p2: Int, payload: Data) {
        guard !payload.isEmpty else { return }
        let bytes = [UInt8](payload)
        let mph = obdTraceReferenceSpeedMph
        let kmh = Int((Double(mph) * 1.609344).rounded())
        guard mph >= 3 else { return } // parked/near-zero values create many false matches.

        func record(type: String, offset: Int, value: Int, reference: Int, unit: String, tolerance: Int) {
            guard value >= 0, value <= 300, abs(value - reference) <= tolerance else { return }
            let key = "hdr=\(command)/\(p1)/\(p2) \(type)@\(offset)≈\(unit)"
            var score = obdSpeedProbeScores[key] ?? OBDSpeedProbeScore()
            score.hits += 1
            score.distinctReferenceSpeeds.insert(reference)
            score.lastValue = value
            obdSpeedProbeScores[key] = score
        }

        for i in bytes.indices {
            let value = Int(bytes[i])
            record(type: "u8", offset: i, value: value, reference: mph, unit: "mph", tolerance: 2)
            record(type: "u8", offset: i, value: value, reference: kmh, unit: "kmh", tolerance: 3)
        }
        if bytes.count >= 2 {
            for i in 0..<(bytes.count - 1) {
                let be = (Int(bytes[i]) << 8) | Int(bytes[i + 1])
                let le = (Int(bytes[i + 1]) << 8) | Int(bytes[i])
                record(type: "u16be", offset: i, value: be, reference: mph, unit: "mph", tolerance: 2)
                record(type: "u16be", offset: i, value: be, reference: kmh, unit: "kmh", tolerance: 3)
                record(type: "u16le", offset: i, value: le, reference: mph, unit: "mph", tolerance: 2)
                record(type: "u16le", offset: i, value: le, reference: kmh, unit: "kmh", tolerance: 3)
            }
        }
        if bytes.count >= 4 {
            for i in 0...(bytes.count - 4) {
                let be = (UInt32(bytes[i]) << 24) | (UInt32(bytes[i + 1]) << 16) | (UInt32(bytes[i + 2]) << 8) | UInt32(bytes[i + 3])
                let le = (UInt32(bytes[i + 3]) << 24) | (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 1]) << 8) | UInt32(bytes[i])
                if be <= 300 {
                    record(type: "u32be", offset: i, value: Int(be), reference: mph, unit: "mph", tolerance: 2)
                    record(type: "u32be", offset: i, value: Int(be), reference: kmh, unit: "kmh", tolerance: 3)
                }
                if le <= 300 {
                    record(type: "u32le", offset: i, value: Int(le), reference: mph, unit: "mph", tolerance: 2)
                    record(type: "u32le", offset: i, value: Int(le), reference: kmh, unit: "kmh", tolerance: 3)
                }
            }
        }
    }

    private func handleDiagnosticPacket(_ body: Data) -> Bool {
        guard body.count >= 3, body[0] == 5, body[1] == 1 else { return false }

        // CrushLogDiagnosticEventPacket: DiagnosticPacket(1,1)
        // UTF category + totalSize + allChunkCount + chunkIndex + chunkSize + bytes.
        if body[2] == 1 {
            var index = 3
            guard let category = readJavaUTF(body, index: &index) else {
                obdDiagnosticMalformedFrameCount += 1
                logger.log("OBD HUD LOG", "Malformed diagnostic chunk: category UTF unreadable bodyBytes=\(body.count) head=\(HudProtocol.hex(body.prefix(96)))")
                return true
            }
            recordObservedDiagnosticCategory(category)
            guard isPlausibleDiagnosticCategory(category) else {
                obdDiagnosticMalformedFrameCount += 1
                logger.log(
                    "OBD HUD LOG",
                    "Rejected diagnostic category bytes category=\(category.debugDescription) bodyBytes=\(body.count) head=\(HudProtocol.hex(body.prefix(96)))"
                )
                return true
            }
            guard let totalSize = int32BE(body, index: &index),
                  let allChunks = int32BE(body, index: &index),
                  let chunkIndex = int32BE(body, index: &index),
                  let chunkSize = int32BE(body, index: &index) else {
                obdDiagnosticMalformedFrameCount += 1
                logger.log("OBD HUD LOG", "Malformed diagnostic header category=\(category) bodyBytes=\(body.count) remaining=\(max(0, body.count-index))")
                return true
            }

            let available = max(0, body.count - index)
            let plausibleHeader = totalSize > 0 && totalSize <= 32 * 1024 * 1024 &&
                allChunks > 0 && allChunks <= 200_000 &&
                chunkIndex >= 0 && chunkIndex < allChunks &&
                chunkSize >= 0 && chunkSize <= 64 * 1024

            // A diagnostic event has no bytes after its declared chunk. The field
            // trace showed repeated/interleaved 20-byte BLE notifications could make
            // `available > chunkSize`; accepting the first N bytes silently stored a
            // corrupted ZIP chunk. Require an exact body length instead.
            guard plausibleHeader, available == chunkSize else {
                obdDiagnosticMalformedFrameCount += 1
                logger.log(
                    "OBD HUD LOG",
                    "Rejected diagnostic fragment category=\(category) total=\(totalSize) chunk=\(chunkIndex + 1)/\(allChunks) declared=\(chunkSize) available=\(available) exact=\(available == chunkSize ? 1 : 0) gps=\(obdTraceReferenceSpeedMph)mph head=\(HudProtocol.hex(body.prefix(128)))"
                )
                return true
            }

            let chunk = body.subdata(in: index..<(index + chunkSize))
            let hits = obdDiagnosticSignatureHits(chunk)
            if chunkIndex < 3 || (chunkIndex + 1) % 25 == 0 || chunkIndex + 1 == allChunks || !hits.isEmpty {
                logger.log(
                    "OBD HUD LOG",
                    "VALID chunk category=\(category) requested=\(obdDiagnosticRequestedCategory) index=\(chunkIndex + 1)/\(allChunks) bytes=\(chunkSize) total=\(totalSize) hits=[\(hits.joined(separator: ","))]"
                )
            }

            // The 2026-09-14 HUD returned LOG_CATEGORY_CRUSH even though the request
            // explicitly named LOG_CATEGORY_OBD. Do not discard a structurally valid
            // returned archive merely because its category label differs. Lock onto
            // the first valid returned category/shape and keep that transfer isolated.
            if obdDiagnosticCategory.isEmpty {
                obdDiagnosticCategory = category
                obdDiagnosticExpectedChunkCount = allChunks
                obdDiagnosticExpectedTotalBytes = totalSize
                obdDiagnosticChunks.removeAll(keepingCapacity: true)
                logger.log(
                    "OBD HUD LOG",
                    "Accepted returned diagnostic stream category=\(category) requested=\(obdDiagnosticRequestedCategory) chunks=\(allChunks) total=\(totalSize)"
                )
            }

            guard category == obdDiagnosticCategory,
                  allChunks == obdDiagnosticExpectedChunkCount,
                  totalSize == obdDiagnosticExpectedTotalBytes else {
                logger.log(
                    "OBD HUD LOG",
                    "Ignoring different diagnostic stream category=\(category) total=\(totalSize) chunks=\(allChunks); active=\(obdDiagnosticCategory) total=\(obdDiagnosticExpectedTotalBytes) chunks=\(obdDiagnosticExpectedChunkCount)"
                )
                return true
            }

            if let existing = obdDiagnosticChunks[chunkIndex] {
                if existing != chunk {
                    obdDiagnosticChunkConflictCount += 1
                    logger.log(
                        "OBD HUD LOG",
                        "Chunk conflict index=\(chunkIndex + 1)/\(allChunks) existingBytes=\(existing.count) newBytes=\(chunk.count) conflicts=\(obdDiagnosticChunkConflictCount); retaining first exact frame"
                    )
                }
            } else {
                obdDiagnosticChunks[chunkIndex] = chunk
            }

            let received = obdDiagnosticChunks.count
            let label = category == obdDiagnosticRequestedCategory
                ? category
                : "\(category) (requested OBD)"
            obdDiagnosticStatus = "Receiving HUD \(label) ZIP • \(received)/\(allChunks) exact chunks"

            if received == allChunks {
                var archive = Data()
                archive.reserveCapacity(totalSize)
                for i in 0..<allChunks {
                    guard let part = obdDiagnosticChunks[i] else { return true }
                    archive.append(part)
                }
                guard archive.count == totalSize else {
                    logger.log("OBD HUD LOG", "Complete chunk set length mismatch assembled=\(archive.count) expected=\(totalSize)")
                    return true
                }

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let safeCategory = category.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
                let extensionName = archive.starts(with: [0x50, 0x4B]) ? "zip" : "bin"
                let filename = "HUD_Diagnostic_\(safeCategory)_\(formatter.string(from: Date())).\(extensionName)"
                do {
                    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                        ?? FileManager.default.temporaryDirectory
                    let url = base.appendingPathComponent(filename)
                    try archive.write(to: url, options: .atomic)
                    obdDiagnosticLogURL = url
                    saveOBDDiagnosticRawCapture(reason: "diagnostic archive completed")
                    obdDiagnosticTransferActive = false
                    obdDiagnosticStatus = "HUD \(category) archive ready • \(archive.count) bytes"
                    logger.log(
                        "OBD HUD LOG",
                        "Saved \(url.lastPathComponent) bytes=\(archive.count) requested=\(obdDiagnosticRequestedCategory) conflicts=\(obdDiagnosticChunkConflictCount)"
                    )
                } catch {
                    saveOBDDiagnosticRawCapture(reason: "diagnostic archive save failed")
                    obdDiagnosticTransferActive = false
                    obdDiagnosticStatus = "Could not save HUD diagnostic archive • raw capture retained"
                    logger.log("OBD HUD LOG", "Save failed: \(error.localizedDescription)")
                }
            }
            return true
        }

        // RemainDiagnosticLogEventPacket: DiagnosticPacket(1,4), int32 bitmap.
        if body[2] == 4 {
            var index = 3
            if let bitmap = int32BE(body, index: &index) {
                let hasOBD = (bitmap & 2) != 0
                logger.log("OBD HUD LOG", "Remaining diagnostic bitmap=\(bitmap) obd=\(hasOBD ? 1 : 0)")
                obdDiagnosticStatus = hasOBD ? "HUD reports OBD diagnostic logs available" : "HUD reports no stored OBD diagnostic logs"
            }
            return true
        }
        return true
    }

    func updateOBDTraceReferenceSpeed(gpsMph: Int) {
        obdTraceReferenceSpeedMph = max(0, gpsMph)
        if obdDeepSpeedProbeActive {
            let now = Date().timeIntervalSinceReferenceDate
            let point = OBDDeepGPSPoint(time: now, mph: obdTraceReferenceSpeedMph)
            if let last = obdDeepGPSPoints.last,
               abs(last.time - point.time) < 0.20,
               last.mph == point.mph {
                // Avoid duplicate GPS callbacks without losing real speed edges.
            } else {
                obdDeepGPSPoints.append(point)
                if obdDeepGPSPoints.count > 600 {
                    obdDeepGPSPoints.removeFirst(obdDeepGPSPoints.count - 600)
                }
            }
        }
        guard obdSpeedTraceEnabled else { return }
        let now = Date()
        guard now.timeIntervalSince(obdTraceLastHeartbeatAt) >= 1.0 else { return }
        obdTraceLastHeartbeatAt = now
        let kmh = Int((Double(obdTraceReferenceSpeedMph) * 1.609344).rounded())
        obdSpeedTraceStatus = "Tracing • GPS \(obdTraceReferenceSpeedMph) mph / \(kmh) km/h • OBD \(obdTraceConnected ? "connected" : "not confirmed")"
        logger.log(
            "OBD TRACE",
            "reference gps=\(obdTraceReferenceSpeedMph)mph \(kmh)kmh hudOBDConnected=\(obdTraceConnected ? 1 : 0)"
        )
    }

    private func obdTraceScalarCandidates(payload: Data) -> [String] {
        guard !payload.isEmpty else { return [] }
        let bytes = [UInt8](payload)
        let mph = obdTraceReferenceSpeedMph
        let kmh = Int((Double(mph) * 1.609344).rounded())
        var matches: [String] = []

        func add(_ text: String) {
            if !matches.contains(text) { matches.append(text) }
        }
        func closeToSpeed(_ value: Int) -> String? {
            if mph > 0, abs(value - mph) <= 3 { return "mph" }
            if kmh > 0, abs(value - kmh) <= 5 { return "kmh" }
            return nil
        }

        for i in bytes.indices {
            let v = Int(bytes[i])
            if let basis = closeToSpeed(v) {
                add("u8@\(i)=\(v)≈\(basis)")
            }
        }
        if bytes.count >= 2 {
            for i in 0..<(bytes.count - 1) {
                let be = (Int(bytes[i]) << 8) | Int(bytes[i + 1])
                let le = (Int(bytes[i + 1]) << 8) | Int(bytes[i])
                if be <= 300, let basis = closeToSpeed(be) { add("u16be@\(i)=\(be)≈\(basis)") }
                if le <= 300, let basis = closeToSpeed(le) { add("u16le@\(i)=\(le)≈\(basis)") }
            }
        }
        if bytes.count >= 4 {
            for i in 0...(bytes.count - 4) {
                let be = (UInt32(bytes[i]) << 24) | (UInt32(bytes[i + 1]) << 16) | (UInt32(bytes[i + 2]) << 8) | UInt32(bytes[i + 3])
                let le = (UInt32(bytes[i + 3]) << 24) | (UInt32(bytes[i + 2]) << 16) | (UInt32(bytes[i + 1]) << 8) | UInt32(bytes[i])
                if be <= 300, let basis = closeToSpeed(Int(be)) { add("u32be@\(i)=\(be)≈\(basis)") }
                if le <= 300, let basis = closeToSpeed(Int(le)) { add("u32le@\(i)=\(le)≈\(basis)") }

                let fbe = Float(bitPattern: be)
                let fle = Float(bitPattern: le)
                if fbe.isFinite, fbe >= 0, fbe <= 300 {
                    let rounded = Int(fbe.rounded())
                    if let basis = closeToSpeed(rounded) { add("f32be@\(i)=\(String(format: "%.2f", fbe))≈\(basis)") }
                }
                if fle.isFinite, fle >= 0, fle <= 300 {
                    let rounded = Int(fle.rounded())
                    if let basis = closeToSpeed(rounded) { add("f32le@\(i)=\(String(format: "%.2f", fle))≈\(basis)") }
                }
            }
        }

        if let ascii = String(data: payload, encoding: .ascii) {
            let trimmed = ascii.trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines))
            if !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) {
                add("ascii=\(trimmed.prefix(48))")
            }
        }
        return matches
    }

    private func tracePossibleOBDSpeedFrame(_ body: Data) {
        guard obdSpeedTraceEnabled, body.count >= 3 else { return }
        let command = Int(body[0])
        let p1 = Int(body[1])
        let p2 = Int(body[2])
        let payload = body.count > 3 ? body.subdata(in: 3..<body.count) : Data()
        let key = "\(command)/\(p1)/\(p2)"
        let signature = HudProtocol.hex(body)
        let now = Date()
        let matches = obdTraceScalarCandidates(payload: payload)

        // Known high-rate housekeeping frames are already decoded elsewhere.
        // Keep them out of the forensic stream unless a scalar happens to track
        // the simultaneous GPS speed. OBD-family events (p1=7/100) are always kept.
        let housekeeping = (p1 == 1 && p2 == 1) || (p1 == 5 && p2 == 0) ||
            (p1 == 6 && p2 == 0) || (p1 == 30 && p2 == 0)
        let force = p1 == 7 || p1 == 100 || !matches.isEmpty
        if housekeeping && !force { return }

        let lastSignature = obdTraceLastFrameSignatureByKey[key]
        let lastAt = obdTraceLastFrameAtByKey[key] ?? .distantPast
        if !force, lastSignature == signature, now.timeIntervalSince(lastAt) < 2.0 { return }
        if force, lastSignature == signature, now.timeIntervalSince(lastAt) < 0.5 { return }
        obdTraceLastFrameSignatureByKey[key] = signature
        obdTraceLastFrameAtByKey[key] = now

        let kmh = Int((Double(obdTraceReferenceSpeedMph) * 1.609344).rounded())
        let candidateText = matches.isEmpty ? "none" : matches.joined(separator: ",")
        logger.log(
            "OBD TRACE RX",
            "hdr=\(key) payloadBytes=\(payload.count) gps=\(obdTraceReferenceSpeedMph)mph/\(kmh)kmh candidates=[\(candidateText)] payload=\(HudProtocol.hex(payload))"
        )
    }

    private func parseVehicleEvent(_ frame: Data) {
        guard let body = HudProtocol.unescape(frame), body.count >= 3 else { return }
        recordOBDDeepSpeedProbeFrame(body)
        logDiagnosticFrameForensics(frame, body: body)
        logOBDSpeedProbeForensics(body)
        if handleDiagnosticPacket(body) { return }
        tracePossibleOBDSpeedFrame(body)

        // Decompiled OBDIIStatusEventPacket: EventPacket(command=3,p1=7,p2=1),
        // payload = int32 status + int32 error. This is connection/update status,
        // not vehicle speed, but logging it separates true OBD-family traffic
        // from any unknown dynamic payload discovered during the drive.
        if body[0] == 3, body[1] == 7, body[2] == 1, body.count >= 11 {
            let status = (Int(body[3]) << 24) | (Int(body[4]) << 16) | (Int(body[5]) << 8) | Int(body[6])
            let error = (Int(body[7]) << 24) | (Int(body[8]) << 16) | (Int(body[9]) << 8) | Int(body[10])
            logger.log("OBD STATUS", "status=\(status) error=\(error)")
            return
        }

        // Experimental brightness diagnostic. Captured traffic contains
        // event command=3, p1=30, p2=0 followed by a big-endian int32.
        // The decompiled app identifies a brightness auto-calculated event.
        // We expose the raw number first and validate it physically before
        // calling it lux or assuming a sensor calibration.
        if body[0] == 3, body[1] == 30, body[2] == 0, body.count >= 7 {
            let value = (Int(body[3]) << 24) | (Int(body[4]) << 16) | (Int(body[5]) << 8) | Int(body[6])
            hudAmbientRawValue = value
            hudAmbientLastUpdated = Date()
            logger.log("HUD LIGHT", "Auto-brightness/sensor raw value = \(value)")
        }

        // HUD firmware/version hello:
        // captured frame unescapes to EventPacket(command=3, p1=5, p2=0)
        // followed by "HUDWAY Drive&<firmware>&<protocol>". This packet
        // reappeared after a physical HUD power cycle even while iOS still
        // considered the BLE link alive. Treat it as a HUD-session reset
        // signal so higher layers can rehydrate persistent configuration.
        if body[0] == 3, body[1] == 5, body[2] == 0 {
            let now = Date()
            if now.timeIntervalSince(lastHUDSessionHelloAt) > 2.0 {
                lastHUDSessionHelloAt = now
                logger.log("HUD SESSION", "Firmware hello/version event detected; HUD state may have reset")
                onHUDSessionReset?()
            }
        }

        // Decompiled WifiSTAStatusEventPacket:
        // EventPacket(command=3, p1=6, p2=0)
        // payload = int32 status + writeUTF(reason) + writeUTF(address).
        if body[0] == 3, body[1] == 6, body[2] == 0, body.count >= 7 {
            let status = (Int(body[3]) << 24) | (Int(body[4]) << 16) | (Int(body[5]) << 8) | Int(body[6])
            var index = 7
            let reason = readJavaUTF(body, index: &index) ?? ""
            let address = readJavaUTF(body, index: &index) ?? ""
            logger.log("HUD WIFI STA", "status=\(status) reason=\(reason.isEmpty ? "—" : reason) address=\(address.isEmpty ? "—" : address)")
            onWiFiSTAStatusEvent?(status, reason, address)
            return
        }

        // Decompiled OBDConnectionEventPacket:
        // EventPacket(command=3, p1=100, p2=0)
        // payload = DataInputStream.readUTF(supportedPids) + boolean connected
        guard body[0] == 3, body[1] == 100, body[2] == 0 else { return }

        var index = 3
        guard body.count >= index + 2 else { return }
        let length = Int(body[index]) << 8 | Int(body[index + 1])
        index += 2
        guard body.count >= index + length + 1 else {
            logger.log("OBD EVENT", "Malformed OBD event frame")
            return
        }

        let textData = body.subdata(in: index..<(index + length))
        let supported = String(data: textData, encoding: .utf8) ?? ""
        index += length
        let connected = body[index] != 0
        obdTraceConnected = connected

        logger.log("OBD EVENT", "connected=\(connected), supported=\(supported)")
        onOBDConnectionEvent?(connected, supported)
    }

    private func onUARTEvent() {
        logger.log("HUD EVENT", "UART connection event -> queue KeepAlive")
        enqueue(HudCommands.keepAlive(), label: "Auto KeepAlive")
    }
}

extension HudBluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.logger.log("BLE", "Central state = \(central.state.rawValue)")
            if central.state == .poweredOn {
                self.attemptedSavedReconnect = false
                if self.autoReconnectEnabled && !self.userRequestedDisconnect {
                    self.reconnectSavedHUDIfPossible()
                }
            } else {
                self.cancelReconnect(reason: "Bluetooth state changed")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String : Any],
                                    rssi RSSI: NSNumber) {
        Task { @MainActor in
            let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = peripheral.name ?? advertisedName ?? "(unnamed)"

            let advertisedServices = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
            let serviceText = advertisedServices.map(\.uuidString).joined(separator: ",")

            self.logger.log(
                "BLE FOUND",
                "\(name) | \(peripheral.identifier) | RSSI \(RSSI) | services=[\(serviceText)]"
            )

            // Keep the UI useful instead of filling it with every anonymous BLE
            // beacon. Always show named devices; HUD devices sort to the top.
            guard name != "(unnamed)" else { return }

            let device = Device(
                id: peripheral.identifier,
                name: name,
                rssi: RSSI.intValue,
                peripheral: peripheral
            )
            if let index = self.devices.firstIndex(where: { $0.id == device.id }) {
                self.devices[index] = device
            } else {
                self.devices.append(device)
            }

            self.devices.sort {
                let lhsHud = $0.name.localizedCaseInsensitiveContains("HUD")
                let rhsHud = $1.name.localizedCaseInsensitiveContains("HUD")
                if lhsHud != rhsHud { return lhsHud && !rhsHud }
                return $0.rssi > $1.rssi
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.logger.log("BLE", "GATT connected: \(peripheral.name ?? peripheral.identifier.uuidString)")
            self.cancelReconnect(reason: "GATT connected")
            self.reconnectAttempt = 0
            self.userRequestedDisconnect = false
            self.autoReconnectEnabled = true
            self.connectedName = peripheral.name ?? "HUD Drive"
            self.ancsAuthorized = peripheral.ancsAuthorized
            self.logger.log("ANCS", "Post-connect ancsAuthorized = \(peripheral.ancsAuthorized)")
            self.saveConnectedHUD(peripheral)
            peripheral.delegate = self
            peripheral.discoverServices([CBUUID(string: HudProtocol.serviceUUID)])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.state = .idle
            self.logger.log(
                "BLE ERROR",
                "Failed to connect \(peripheral.name ?? peripheral.identifier.uuidString): \(error?.localizedDescription ?? "unknown error")"
            )
            if self.autoReconnectEnabled && !self.userRequestedDisconnect {
                self.scheduleReconnect(reason: "connection attempt failed")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        Task { @MainActor in
            self.ancsAuthorized = peripheral.ancsAuthorized
            self.logger.log(
                "ANCS",
                "Authorization changed: ancsAuthorized = \(peripheral.ancsAuthorized)"
            )
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            self.state = .idle
            self.connectedName = nil
            self.ancsAuthorized = false
            self.txCharacteristic = nil
            self.rxCharacteristic = nil
            self.txQueue.removeAll()
            self.currentChunks.removeAll()
            self.writing = false
            let reason = error?.localizedDescription ?? "no error"
            if self.obdDiagnosticTransferActive {
                self.saveOBDDiagnosticRawCapture(reason: "HUD BLE disconnected: \(reason)")
                self.obdDiagnosticTransferActive = false
                if self.obdDiagnosticRawCaptureURL != nil {
                    self.obdDiagnosticStatus = "HUD disconnected • raw capture saved"
                }
            }
            self.endOBDSpeedProbeForensics(reason: "HUD BLE disconnected")
            self.logger.log("BLE", "Disconnected: \(reason)")
            self.onTransportDisconnected?()

            if self.userRequestedDisconnect {
                self.logger.log("BLE AUTO", "No reconnect: disconnect was user-requested")
            } else if self.autoReconnectEnabled {
                self.scheduleReconnect(reason: "unexpected disconnect: \(reason)")
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    willRestoreState dict: [String : Any]) {
        Task { @MainActor in
            self.logger.log("BLE", "CoreBluetooth restoration callback")
            if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
               let restored = peripherals.first {
                self.logger.log(
                    "BLE AUTO",
                    "Restored peripheral \(restored.name ?? restored.identifier.uuidString)"
                )
                self.peripheral = restored
                restored.delegate = self
                self.saveConnectedHUD(restored)
            }
        }
    }
}

extension HudBluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error { self.logger.log("ERROR", "Service discovery: \(error.localizedDescription)") }
            guard let service = peripheral.services?.first(where: {
                $0.uuid == CBUUID(string: HudProtocol.serviceUUID)
            }) else {
                self.logger.log("ERROR", "HUD NUS service not found")
                return
            }
            peripheral.discoverCharacteristics([
                CBUUID(string: HudProtocol.writeUUID),
                CBUUID(string: HudProtocol.notifyUUID)
            ], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            if let error { self.logger.log("ERROR", "Characteristic discovery: \(error.localizedDescription)") }
            for characteristic in service.characteristics ?? [] {
                if characteristic.uuid == CBUUID(string: HudProtocol.writeUUID) {
                    self.txCharacteristic = characteristic
                } else if characteristic.uuid == CBUUID(string: HudProtocol.notifyUUID) {
                    self.rxCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
            if self.txCharacteristic != nil && self.rxCharacteristic != nil {
                self.state = .connected
                self.cancelReconnect(reason: "HUD transport ready")
                self.reconnectAttempt = 0
                self.logger.log("BLE", "HUD transport ready; reconnect watchdog armed")
                self.enqueue(HudCommands.uartConnectionCheck(), label: "UART connection check")
                self.onTransportReady?()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value else { return }
            self.lastRX = HudProtocol.hex(data)
            // Preserve every diagnostic notification in the bounded binary capture
            // before any de-duplication. Exact immediate continuation duplicates are
            // intentionally omitted from both the frame parser and verbose RX CHUNK
            // text log so a forensic download cannot flood the main actor/log UI.
            self.captureOBDDiagnosticRawBLE(data)
            if self.shouldSuppressDuplicateDiagnosticBLEFragment(data) { return }

            // Large diagnostic transfers can exceed four thousand BLE notifications.
            // Logging every compressed continuation on the main actor adds enough UI/
            // file-I/O pressure to make notification loss more likely. Feed diagnostic
            // fragments directly into the dedicated reassembler first; ordinary
            // interleaved HUD events still fall through to the normal RX logger/parser.
            if self.consumeDiagnosticBLEFragment(data) { return }
            self.logger.log("RX CHUNK", self.lastRX)

            self.rxBuffer.append(data)
            let frames = HudProtocol.extractFrames(from: &self.rxBuffer)
            for frame in frames {
                self.logger.log("RX", HudProtocol.hex(frame))
                if HudProtocol.isUARTConnectionEvent(frame) {
                    self.onUARTEvent()
                }
                self.parseVehicleEvent(frame)
            }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            guard let characteristic = self.txCharacteristic else { return }
            self.writeNextChunk(peripheral: peripheral, characteristic: characteristic)
        }
    }
}
