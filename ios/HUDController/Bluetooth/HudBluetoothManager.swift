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
    private(set) var obdDiagnosticTransferActive = false
    private var obdDiagnosticChunks: [Int: Data] = [:]
    private var obdDiagnosticExpectedChunkCount = 0
    private var obdDiagnosticExpectedTotalBytes = 0
    private var obdDiagnosticCategory = ""

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
        obdDiagnosticChunks.removeAll(keepingCapacity: true)
        obdDiagnosticExpectedChunkCount = 0
        obdDiagnosticExpectedTotalBytes = 0
        obdDiagnosticCategory = "LOG_CATEGORY_OBD"
        obdDiagnosticLogURL = nil
        obdDiagnosticTransferActive = true
        obdDiagnosticStatus = "Requesting HUD OBD diagnostic ZIP…"
        logger.log("OBD HUD LOG", "Request LOG_CATEGORY_OBD maxLastFilesCount=\(maxLastFilesCount)")
        enqueue(
            HudCommands.requestOBDDiagnosticLogs(maxLastFilesCount: maxLastFilesCount),
            label: "Request HUD OBD diagnostic logs"
        )
    }

    func cancelOBDDiagnosticLogs() {
        guard state == .connected else { return }
        enqueue(HudCommands.cancelDiagnosticLogTransfer(), label: "Cancel HUD diagnostic log transfer")
        obdDiagnosticTransferActive = false
        obdDiagnosticStatus = "Transfer cancelled"
        logger.log("OBD HUD LOG", "Transfer cancelled by user")
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

    private func handleDiagnosticPacket(_ body: Data) -> Bool {
        guard body.count >= 3, body[0] == 5, body[1] == 1 else { return false }

        // CrushLogDiagnosticEventPacket: DiagnosticPacket(1,1)
        // UTF category + totalSize + allChunkCount + chunkIndex + chunkSize + bytes.
        if body[2] == 1 {
            var index = 3
            guard let category = readJavaUTF(body, index: &index),
                  let totalSize = int32BE(body, index: &index),
                  let allChunks = int32BE(body, index: &index),
                  let chunkIndex = int32BE(body, index: &index),
                  let chunkSize = int32BE(body, index: &index),
                  chunkSize >= 0, body.count >= index + chunkSize else {
                logger.log("OBD HUD LOG", "Malformed diagnostic chunk payloadBytes=\(max(0, body.count - 3))")
                return true
            }
            let chunk = body.subdata(in: index..<(index + chunkSize))
            logger.log(
                "OBD HUD LOG",
                "chunk category=\(category) index=\(chunkIndex + 1)/\(allChunks) bytes=\(chunkSize) total=\(totalSize)"
            )
            guard category == "LOG_CATEGORY_OBD" else { return true }
            if !obdDiagnosticTransferActive {
                obdDiagnosticTransferActive = true
                obdDiagnosticChunks.removeAll(keepingCapacity: true)
            }
            obdDiagnosticCategory = category
            obdDiagnosticExpectedChunkCount = max(0, allChunks)
            obdDiagnosticExpectedTotalBytes = max(0, totalSize)
            if chunkIndex >= 0 { obdDiagnosticChunks[chunkIndex] = chunk }
            let received = obdDiagnosticChunks.count
            obdDiagnosticStatus = "Receiving HUD OBD ZIP • \(received)/\(max(1, allChunks)) chunks"

            if allChunks > 0, received == allChunks {
                var zip = Data()
                zip.reserveCapacity(max(0, totalSize))
                for i in 0..<allChunks {
                    guard let part = obdDiagnosticChunks[i] else { return true }
                    zip.append(part)
                }
                if totalSize > 0, zip.count > totalSize {
                    zip = Data(zip.prefix(totalSize))
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let filename = "HUD_OBD_Diagnostic_\(formatter.string(from: Date())).zip"
                do {
                    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                        ?? FileManager.default.temporaryDirectory
                    let url = base.appendingPathComponent(filename)
                    try zip.write(to: url, options: .atomic)
                    obdDiagnosticLogURL = url
                    obdDiagnosticTransferActive = false
                    obdDiagnosticStatus = "HUD OBD ZIP ready • \(zip.count) bytes"
                    logger.log("OBD HUD LOG", "Saved \(url.lastPathComponent) bytes=\(zip.count) expected=\(totalSize)")
                } catch {
                    obdDiagnosticTransferActive = false
                    obdDiagnosticStatus = "Could not save HUD OBD ZIP"
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
