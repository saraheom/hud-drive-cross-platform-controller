import SwiftUI
import UniformTypeIdentifiers

/// Global app settings opened from the persistent top-right gear button.
///
/// Display calibration mirrors the original HUDWAY Drive 1.4.6 Advanced page.
/// Firmware maintenance is intentionally kept here (rather than Navigation)
/// because it is a device-level operation, not a driving/navigation control.
struct HudSettingsView: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showBootAnimationImporter = false
    @State private var confirmBootInstall = false
    @State private var confirmBootRestore = false
    @State private var confirmHUDReboot = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    displayCalibrationCard
                    firmwareMaintenanceCard
                }
                .padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showBootAnimationImporter,
            allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, .movie, .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await state.maintenance.prepareAnimation(from: url) }
            case .failure(let error):
                state.maintenance.lastError = error.localizedDescription
                state.maintenance.status = "File selection failed: \(error.localizedDescription)"
            }
        }
        .alert("Install custom boot animation?", isPresented: $confirmBootInstall) {
            Button("Cancel", role: .cancel) {}
            Button("Install") {
                Task { await state.maintenance.installPreparedOverride() }
            }
        } message: {
            Text("This writes only /data/local/bootanimation/bootanimation.zip, verifies the complete file by ADB read-back SHA-256, and leaves /system/media/bootanimation.zip untouched.")
        }
        .alert("Restore stock boot animation?", isPresented: $confirmBootRestore) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                Task { await state.maintenance.restoreStockFallback() }
            }
        } message: {
            Text("This deletes only the /data/local bootanimation override. The original /system animation remains unchanged.")
        }
        .alert("Reboot HUD now?", isPresented: $confirmHUDReboot) {
            Button("Cancel", role: .cancel) {}
            Button("Reboot", role: .destructive) {
                Task { await state.maintenance.rebootHUD() }
            }
        } message: {
            Text("The HUD Wi-Fi and ADB connection will disappear during reboot. Keep vehicle/HUD power stable until it finishes starting.")
        }
    }

    private var displayCalibrationCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HUD Display")
                            .font(.headline)
                        Text("Original HUDWAY Scale + Perspective")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "rectangle.on.rectangle")
                        .foregroundStyle(HudTheme.accent)
                }

                calibrationSlider(
                    title: "Scale",
                    value: state.settings.displayScaleAdjustment,
                    wireValue: state.settings.displayScaleWireValue,
                    maximumWireValue: 0.20,
                    perspective: false
                ) { value in
                    state.setDisplayScaleAdjustment(value)
                }

                Divider()

                calibrationSlider(
                    title: "Perspective",
                    value: state.settings.displayPerspectiveAdjustment,
                    wireValue: state.settings.displayPerspectiveWireValue,
                    maximumWireValue: 0.10,
                    perspective: true
                ) { value in
                    state.setDisplayPerspectiveAdjustment(value)
                }

                HStack {
                    Button("Reset to Stock") {
                        state.resetDisplayCalibrationToStock()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if state.bluetooth.state == .connected {
                        Label("Live", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(HudTheme.accent)
                    } else {
                        Text("Saved; applies on reconnect")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HudDescription("The stock app maps each 0–100 slider to a firmware Float32: Scale → 0.00–0.20 using LayoutSizeCommandPacket, Perspective → 0.00–0.10 using KeyStoneCommandPacket. Changes are saved and reasserted after HUD reconnect/reboot.")

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Per-widget scale / perspective")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("Research")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    HudDescription("The recovered stock protocol does not expose a safe per-widget variant: the Scale and Keystone packets contain only one Float32 and no left/center/right widget identifier, while the dashboard packet only selects widget names. This build therefore keeps calibration global instead of inventing an unverified packet. Per-widget rendering remains a read-only firmware research target.")
                }
            }
        }
    }

    @ViewBuilder
    private func calibrationSlider(
        title: String,
        value: Int,
        wireValue: Float,
        maximumWireValue: Float,
        perspective: Bool,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                Text("\(value)")
                    .font(.system(.body, design: .monospaced).bold())
                    .foregroundStyle(HudTheme.accent)
            }

            HStack(spacing: 12) {
                CalibrationGlyph(perspective: false, compact: false)
                    .frame(width: 30, height: 24)

                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { onChange(Int($0.rounded())) }
                    ),
                    in: 0...100,
                    step: 1
                )

                CalibrationGlyph(perspective: perspective, compact: !perspective)
                    .frame(width: 30, height: 24)
            }

            Text(String(format: "Firmware value %.4f / %.2f", Double(wireValue), Double(maximumWireValue)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var firmwareMaintenanceCard: some View {
        HudCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("HUD Firmware Maintenance")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(HudTheme.accent)
                }

                LabeledContent("HUD Wi-Fi", value: state.hudWiFiExpectedSSID)
                LabeledContent("Password", value: "87654321")
                LabeledContent("HUD IP / ADB", value: "192.168.43.1:5555")
                LabeledContent("ADB", value: state.maintenance.adbState.rawValue)
                LabeledContent("HUD", value: state.maintenance.hudIdentity)
                LabeledContent("Boot animation", value: state.maintenance.overrideStatus)

                if !state.firmwareMaintenanceActive {
                    Button("Start Firmware Maintenance") {
                        state.startFirmwareMaintenance()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.bluetooth.state != .connected)
                } else {
                    HStack {
                        Button("Reconnect ADB") {
                            state.reconnectFirmwareMaintenanceADB()
                        }
                        Button("Exit Maintenance Mode") {
                            state.exitFirmwareMaintenance()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                Text(state.maintenance.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Boot Animation Override")
                    .font(.subheadline.bold())
                HudDescription("The HUD bootanimation binary checks /data/local/bootanimation/bootanimation.zip before the untouched stock /system/media/bootanimation.zip. The installer writes only the data/local override and verifies it by complete ADB read-back.")

                Button("Select Video or bootanimation.zip") {
                    showBootAnimationImporter = true
                }
                .buttonStyle(.bordered)
                .disabled(state.maintenance.busy)

                LabeledContent("Prepared", value: state.maintenance.preparedSummary)
                LabeledContent("SHA-256", value: state.maintenance.preparedHashShort)

                if state.maintenance.preparationProgress > 0 && state.maintenance.preparationProgress < 1 {
                    ProgressView(value: state.maintenance.preparationProgress)
                }
                if state.maintenance.transferProgress > 0 && state.maintenance.transferProgress < 1 {
                    ProgressView("Uploading / verifying…", value: state.maintenance.transferProgress)
                }

                HStack {
                    Button("Install Custom Boot Animation") {
                        confirmBootInstall = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.maintenance.adbState != .connected || state.maintenance.prepared == nil || state.maintenance.busy)

                    Button("Restore Stock") {
                        confirmBootRestore = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.maintenance.adbState != .connected || state.maintenance.busy)
                }

                Button("Reboot HUD to Test Animation") {
                    confirmHUDReboot = true
                }
                .buttonStyle(.bordered)
                .disabled(state.maintenance.adbState != .connected || state.maintenance.busy)

                if let error = state.maintenance.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HudDescription("Video import is converted locally to the HUD's native 480×240, 24-fps Android bootanimation format and remains limited to 12 seconds. Restore Stock deletes only the override; it never remounts or modifies /system.")
            }
        }
    }
}

/// Simple vector glyphs so this settings page does not depend on a particular
/// SF Symbol version for the stock HUDWAY scale/perspective visual language.
private struct CalibrationGlyph: View {
    let perspective: Bool
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let w = proxy.size.width
                let h = proxy.size.height
                if perspective {
                    path.move(to: CGPoint(x: w * 0.22, y: h * 0.82))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.82))
                    path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.18))
                    path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.18))
                    path.closeSubpath()
                } else {
                    let inset = compact ? w * 0.24 : w * 0.12
                    path.addRect(CGRect(x: inset, y: h * 0.18, width: w - inset * 2, height: h * 0.64))
                }
            }
            .stroke(.primary, lineWidth: 2.4)
        }
    }
}
