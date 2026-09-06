import Foundation
import Observation

@MainActor
@Observable
final class HudMaintenanceManager {
    enum ADBState: String {
        case disconnected = "Disconnected"
        case connecting = "Connecting…"
        case connected = "Connected"
        case failed = "Failed"
    }

    static let hudHost = "192.168.43.1"
    static let hudPort: UInt16 = 5555
    static let wifiPassword = "87654321"
    static let remoteDirectory = "/data/local/bootanimation"
    static let remoteOverride = "/data/local/bootanimation/bootanimation.zip"
    static let remotePending = "/data/local/bootanimation/bootanimation.zip.pending"

    private let logger: LogManager
    private let adb = HUDADBClient()

    private(set) var adbState: ADBState = .disconnected
    var status = "Maintenance mode not started"
    private(set) var hudIdentity = "Not queried"
    private(set) var overrideStatus = "Unknown"
    private(set) var prepared: PreparedBootAnimation?
    private(set) var preparationProgress = 0.0
    private(set) var transferProgress = 0.0
    private(set) var busy = false
    var lastError: String?

    init(logger: LogManager) {
        self.logger = logger
    }

    var preparedSummary: String {
        guard let prepared else { return "No animation selected" }
        let mb = Double(prepared.byteCount) / 1_048_576.0
        return String(format: "%@ • %d frames • %.1fs • %.2f MB", prepared.sourceName, prepared.frameCount, prepared.durationSeconds, mb)
    }

    var preparedHashShort: String {
        guard let hash = prepared?.sha256 else { return "—" }
        return String(hash.prefix(16)) + "…"
    }

    func connectADB(retries: Int = 8) async throws {
        adbState = .connecting
        lastError = nil
        var finalError: Error?
        for attempt in 1...max(1, retries) {
            do {
                try await adb.connect(host: Self.hudHost, port: Self.hudPort)
                adbState = .connected
                status = "ADB connected to 192.168.43.1:5555"
                logger.log("HUD ADB", "Connected without AUTH to \(Self.hudHost):\(Self.hudPort) attempt=\(attempt)")
                try await refreshHUDIdentity()
                try await refreshOverrideStatus()
                return
            } catch {
                finalError = error
                await adb.disconnect()
                logger.log("HUD ADB", "Connect attempt \(attempt)/\(retries) failed: \(error.localizedDescription)")
                try? await Task.sleep(for: .milliseconds(850))
            }
        }
        adbState = .failed
        let message = finalError?.localizedDescription ?? "Unknown ADB error"
        lastError = message
        status = message
        throw finalError ?? HUDADBClient.ADBError.connectionFailed(message)
    }

    func disconnectADB() {
        Task { await adb.disconnect() }
        adbState = .disconnected
    }

    func refreshHUDIdentity() async throws {
        let model = try await adb.shell("getprop ro.kivic.model")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firmware = try await adb.shell("getprop ro.kivic.firmware.version")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let adbSecure = try await adb.shell("getprop ro.adb.secure")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        hudIdentity = "\(model.isEmpty ? "?" : model) • FW \(firmware.isEmpty ? "?" : firmware) • adb.secure=\(adbSecure.isEmpty ? "?" : adbSecure)"
        guard model == "HUDWAY Drive" else {
            throw HUDADBClient.ADBError.unexpectedTarget("ro.kivic.model=\(model.isEmpty ? "<empty>" : model)")
        }
        guard firmware == "1.1.27" else {
            throw HUDADBClient.ADBError.unexpectedTarget("this write path is validated only for HUD FW 1.1.27; device reports \(firmware.isEmpty ? "<empty>" : firmware)")
        }
        guard adbSecure == "0" else {
            throw HUDADBClient.ADBError.unexpectedTarget("expected ro.adb.secure=0; device reports \(adbSecure.isEmpty ? "<empty>" : adbSecure)")
        }
        logger.log("HUD ADB", "Verified identity \(hudIdentity)")
    }

    func refreshOverrideStatus() async throws {
        let output = try await adb.shell("if [ -f \(Self.remoteOverride) ]; then ls -l \(Self.remoteOverride); else echo STOCK_FALLBACK; fi")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        overrideStatus = output.contains("STOCK_FALLBACK") ? "Stock fallback active" : "Custom override installed"
        logger.log("BOOT ANIM", "Override status: \(output)")
    }

    func prepareAnimation(from url: URL) async {
        busy = true
        lastError = nil
        preparationProgress = 0
        status = "Preparing boot animation…"
        defer { busy = false }
        do {
            let result = try await BootAnimationBuilder.prepare(from: url) { [weak self] progress, message in
                Task { @MainActor in
                    self?.preparationProgress = progress
                    self?.status = message
                }
            }
            prepared = result
            preparationProgress = 1
            status = "Animation package ready"
            logger.log("BOOT ANIM", "Prepared source=\(result.sourceName) frames=\(result.frameCount) duration=\(String(format: "%.2f", result.durationSeconds))s bytes=\(result.byteCount) sha256=\(result.sha256)")
        } catch {
            prepared = nil
            lastError = error.localizedDescription
            status = error.localizedDescription
            logger.log("BOOT ANIM", "Preparation failed: \(error.localizedDescription)")
        }
    }

    func installPreparedOverride() async {
        guard adbState == .connected else {
            lastError = "Connect ADB before installing the boot animation."
            return
        }
        guard let prepared else {
            lastError = "Select and prepare an animation first."
            return
        }

        busy = true
        lastError = nil
        transferProgress = 0
        status = "Checking safe override directory…"
        defer { busy = false }

        do {
            // Re-verify the exact physical target immediately before the write.
            try await refreshHUDIdentity()
            let preflight = try await adb.shell("if [ -d \(Self.remoteDirectory) ] && [ -w \(Self.remoteDirectory) ]; then echo READY; else echo NOT_WRITABLE; fi")
            guard preflight.contains("READY") else {
                throw HUDADBClient.ADBError.syncFailed("\(Self.remoteDirectory) is not writable by the ADB shell user; no write was attempted.")
            }

            _ = try await adb.shell("rm -f \(Self.remotePending)")
            status = "Uploading boot animation override…"
            try await adb.push(localURL: prepared.url, remotePath: Self.remotePending) { [weak self] sent, total in
                Task { @MainActor in
                    self?.transferProgress = total > 0 ? Double(sent) / Double(total) : 0
                }
            }

            status = "Read-back verifying SHA-256…"
            let remote = try await adb.hashRemoteFile(Self.remotePending)
            guard remote.byteCount == prepared.byteCount else {
                throw HUDADBClient.ADBError.syncFailed("Read-back size mismatch local=\(prepared.byteCount) remote=\(remote.byteCount)")
            }
            guard remote.sha256.caseInsensitiveCompare(prepared.sha256) == .orderedSame else {
                throw HUDADBClient.ADBError.syncFailed("Read-back SHA-256 mismatch")
            }

            let commit = try await adb.shell("mv \(Self.remotePending) \(Self.remoteOverride) && chmod 0644 \(Self.remoteOverride) && echo COMMITTED")
            guard commit.contains("COMMITTED") else {
                throw HUDADBClient.ADBError.syncFailed("HUD did not confirm atomic override commit")
            }

            let installed = try await adb.hashRemoteFile(Self.remoteOverride)
            guard installed.sha256.caseInsensitiveCompare(prepared.sha256) == .orderedSame else {
                throw HUDADBClient.ADBError.syncFailed("Final installed SHA-256 mismatch")
            }

            transferProgress = 1
            overrideStatus = "Custom override installed — reboot to test"
            status = "Boot animation installed and verified"
            logger.log("BOOT ANIM", "Installed override path=\(Self.remoteOverride) bytes=\(installed.byteCount) sha256=\(installed.sha256)")
        } catch {
            _ = try? await adb.shell("rm -f \(Self.remotePending)")
            lastError = error.localizedDescription
            status = error.localizedDescription
            logger.log("BOOT ANIM", "Install failed safely: \(error.localizedDescription)")
        }
    }

    func restoreStockFallback() async {
        guard adbState == .connected else {
            lastError = "Connect ADB before restoring the stock animation."
            return
        }
        busy = true
        lastError = nil
        defer { busy = false }
        do {
            status = "Removing only the /data/local boot-animation override…"
            let result = try await adb.shell("rm -f \(Self.remoteOverride) \(Self.remotePending); if [ ! -e \(Self.remoteOverride) ]; then echo RESTORED; fi")
            guard result.contains("RESTORED") else {
                throw HUDADBClient.ADBError.syncFailed("Could not confirm override deletion")
            }
            overrideStatus = "Stock fallback active — reboot to test"
            status = "Custom override removed; /system/media/bootanimation.zip was untouched"
            logger.log("BOOT ANIM", "Removed data/local override; stock system animation remains untouched")
        } catch {
            lastError = error.localizedDescription
            status = error.localizedDescription
            logger.log("BOOT ANIM", "Restore failed: \(error.localizedDescription)")
        }
    }

    func rebootHUD() async {
        guard adbState == .connected else {
            lastError = "ADB is not connected."
            return
        }
        busy = true
        lastError = nil
        status = "Reboot command sent; HUD Wi-Fi/ADB will disconnect"
        logger.log("HUD ADB", "User-confirmed reboot requested after boot-animation operation")
        do {
            try await adb.reboot()
            adbState = .disconnected
        } catch {
            // A successful reboot commonly tears the socket down immediately.
            adbState = .disconnected
            logger.log("HUD ADB", "Reboot transport closed: \(error.localizedDescription)")
        }
        busy = false
    }
}
