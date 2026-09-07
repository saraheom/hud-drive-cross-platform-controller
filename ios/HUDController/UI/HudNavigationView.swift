import SwiftUI
import Foundation
import PhotosUI
import UniformTypeIdentifiers

struct HudNavigationView: View {
    @Bindable var state: AppState
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoStatus = ""
    @State private var showBootAnimationImporter = false
    @State private var confirmBootInstall = false
    @State private var confirmBootRestore = false
    @State private var confirmHUDReboot = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    RouteGuidanceStatusCard(state: state)

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Navigation presentation").font(.headline)
                            Toggle("Show Current Street", isOn: Binding(
                                get: { state.settings.navigationShowCurrentStreet },
                                set: { value in
                                    state.settings.navigationShowCurrentStreet = value
                                    state.applyNavigationPresentationSettings()
                                }
                            ))
                            Picker("Lane Guidance", selection: Binding(
                                get: { state.settings.laneGuidanceMode },
                                set: { value in
                                    state.settings.laneGuidanceMode = value
                                    state.applyNavigationPresentationSettings()
                                }
                            )) {
                                ForEach(HudLaneGuidanceMode.allCases) { mode in Text(mode.title).tag(mode) }
                            }
                            .pickerStyle(.segmented)

                            Picker("Lane placement", selection: Binding(
                                get: { state.settings.lanePlacementMode },
                                set: { value in
                                    state.settings.lanePlacementMode = value
                                    state.applyNavigationPresentationSettings()
                                }
                            )) {
                                ForEach(HudLanePlacementMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)

                            if state.settings.lanePlacementMode != .centerNative {
                                Text("Right-side probe keeps the normal center Navigation renderer and temporarily replaces ETA with the selected stock candidate only while lanes are eligible. If the firmware supports a side lane renderer, a right-side lane response should appear. The stock center gray lane box may still remain during this probe. Normal ETA is restored automatically when lanes hide.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if state.settings.laneGuidanceMode == .nearTurn {
                                Text(String(format: "Show lanes within %.1f mi (~%d ft)", state.settings.laneGuidanceDistanceMiles, Int((state.settings.laneGuidanceDistanceMiles * 5280).rounded())))
                                    .font(.subheadline)
                                Slider(value: Binding(
                                    get: { state.settings.laneGuidanceDistanceMiles },
                                    set: { value in
                                        state.settings.laneGuidanceDistanceMiles = value
                                        state.applyNavigationPresentationSettings()
                                    }
                                ), in: 0.1...1.0, step: 0.1)
                            }
                            Text("Live U2W v8.8 active-event resolution remains unchanged. Center (stock) keeps the proven renderer. The two right-side choices are safe stock-widget probes for this field test.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HUD Firmware Maintenance").font(.headline)
                            LabeledContent("HUD Wi-Fi", value: state.hudWiFiExpectedSSID)
                            LabeledContent("Password", value: "87654321")
                            LabeledContent("HUD IP / ADB", value: "192.168.43.1:5555")
                            LabeledContent("ADB", value: state.maintenance.adbState.rawValue)
                            LabeledContent("HUD", value: state.maintenance.hudIdentity)
                            LabeledContent("Boot animation", value: state.maintenance.overrideStatus)

                            if !state.firmwareMaintenanceActive {
                                Button("Start Firmware Maintenance") { state.startFirmwareMaintenance() }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(state.bluetooth.state != .connected)
                            } else {
                                HStack {
                                    Button("Reconnect ADB") { state.reconnectFirmwareMaintenanceADB() }
                                    Button("Exit Maintenance Mode") { state.exitFirmwareMaintenance() }
                                }.buttonStyle(.bordered)
                            }
                            Text(state.maintenance.status).font(.caption).foregroundStyle(.secondary)
                            Divider()
                            Text("Boot Animation Override").font(.subheadline.bold())
                            Button("Select Video or bootanimation.zip") { showBootAnimationImporter = true }
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
                                Button("Install Custom Boot Animation") { confirmBootInstall = true }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(state.maintenance.adbState != .connected || state.maintenance.prepared == nil || state.maintenance.busy)
                                Button("Restore Stock") { confirmBootRestore = true }
                                    .buttonStyle(.bordered)
                                    .disabled(state.maintenance.adbState != .connected || state.maintenance.busy)
                            }
                            Button("Reboot HUD to Test Animation") { confirmHUDReboot = true }
                                .buttonStyle(.bordered)
                                .disabled(state.maintenance.adbState != .connected || state.maintenance.busy)
                            if let error = state.maintenance.lastError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            Text("Writes only /data/local/bootanimation/bootanimation.zip and verifies it by ADB read-back SHA-256. Restore Stock deletes that override; /system/media/bootanimation.zip is never changed.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(spacing: 14) {
                            Image(systemName: state.navigation.current.maneuver.symbol)
                                .font(.system(size: 64, weight: .semibold))
                            Text(state.navigation.current.primaryText).font(.title2.bold())
                            Text(state.navigation.current.streetName).font(.headline).foregroundStyle(.secondary)
                            Text(distanceText(state.navigation.current))
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(HudTheme.accent)
                        }.frame(maxWidth: .infinity)
                    }

                    if #available(iOS 27.0, *),
                       let capture = state.externalCapture27 as? ExternalNavigationCapture {
                        HudCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Automatic External Maps Capture").font(.headline)
                                Text(capture.status).font(.caption).foregroundStyle(.secondary)

                                Toggle("Automatically send parsed maneuver to HUD", isOn: Binding(
                                    get: { capture.autoSendToHUD },
                                    set: { capture.autoSendToHUD = $0 }
                                ))

                                Toggle("Auto-enable HUD navigation after valid OCR", isOn: Binding(
                                    get: { capture.autoEnableNavigationMode },
                                    set: { capture.autoEnableNavigationMode = $0 }
                                ))

                                Toggle("Keep screen awake during capture", isOn: Binding(
                                    get: { capture.keepScreenAwake },
                                    set: { capture.keepScreenAwake = $0 }
                                ))

                                Toggle("Try automatic capture recovery", isOn: Binding(
                                    get: { capture.autoRecoverAfterInterruption },
                                    set: { capture.autoRecoverAfterInterruption = $0 }
                                ))

                                if capture.needsUserReselection {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label("Screen capture needs to be resumed", systemImage: "exclamationmark.triangle.fill")
                                            .font(.subheadline.bold())
                                        Text("iOS ended the previous full-display stream. Tap Resume Capture, then choose Entire Display in Apple's system picker.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Button("Resume Capture") {
                                            capture.presentFullDisplayPicker()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding(10)
                                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                }

                                HStack {
                                    Button("Start Full-Display Capture") {
                                        capture.presentFullDisplayPicker()
                                    }.buttonStyle(.borderedProminent)
                                    Button("Stop") { capture.stop() }.buttonStyle(.bordered)
                                }

                                Divider()
                                Text("Saved screenshot test").font(.subheadline.bold())
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Label("Choose Maps Screenshot", systemImage: "photo")
                                }
                                .buttonStyle(.bordered)
                                .onChange(of: selectedPhoto) { _, item in
                                    guard let item else { return }
                                    Task {
                                        do {
                                            if let data = try await item.loadTransferable(type: Data.self),
                                               let image = UIImage(data: data) {
                                                await capture.analyzePhoto(image)
                                                state.navigation.current = capture.latestInstruction
                                                photoStatus = "Parsed and copied into maneuver fields"
                                            } else {
                                                photoStatus = "Could not load selected image"
                                            }
                                        } catch {
                                            photoStatus = error.localizedDescription
                                        }
                                    }
                                }
                                if !photoStatus.isEmpty {
                                    Text(photoStatus).font(.caption).foregroundStyle(.secondary)
                                }

                                LabeledContent("Detected source", value: capture.detectedSource.rawValue)
                                LabeledContent("Screen state", value: capture.detectedScreenState.rawValue)
                                LabeledContent("Parsed maneuver", value: capture.latestInstruction.maneuver.label)
                                LabeledContent("Distance", value: distanceText(capture.latestInstruction))
                                LabeledContent("Street", value: capture.latestInstruction.streetName.isEmpty ? "—" : capture.latestInstruction.streetName)
                                LabeledContent("Frames OCR'd", value: "\(capture.frameCount)")
                                LabeledContent("Valid navigation frames", value: "\(capture.validNavigationFrames)")
                                LabeledContent("Rejected frames", value: "\(capture.rejectedFrames)")
                                LabeledContent("HUD navigation armed", value: capture.navigationModeArmed ? "Yes" : "No")

                                DisclosureGroup("Latest OCR text") {
                                    Text(capture.latestRawText.isEmpty ? "No OCR yet" : capture.latestRawText)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }

                                Text("""
                                Google Maps and Apple Maps are detected automatically from OCR/layout evidence; there is no source selector. Valid route lists automatically enter Navigation mode. Apple Maps “Proceed to the route” is treated as active navigation, reroutes can replace the entire current maneuver immediately when the new layout is structurally valid, and normal Maps home/map screens return the HUD to Freeride after confirmation.

                                Screen capture is treated as a long-lived driving service. Raw ScreenCaptureKit frames feed a heartbeat independently of OCR. If that heartbeat dies, the HUD immediately returns to Freeride while the app rebuilds the stream. After repeated failures of the cached filter, the app invalidates it and asks for a fresh Entire Display selection instead of leaving navigation frozen.
                                """)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HudCard {
                            Text("ScreenCaptureKit full-display navigation capture requires iOS 27 or later.")
                                .font(.caption)
                        }
                    }

                    HudCard {
                        Picker("Maneuver", selection: Binding(
                            get: { state.navigation.current.maneuver },
                            set: { state.navigation.current.maneuver = $0 }
                        )) {
                            ForEach(HudManeuver.allCases) { m in Text(m.label).tag(m) }
                        }
                        TextField("Distance (m)", value: Binding(
                            get: { state.navigation.current.distanceMeters },
                            set: { state.navigation.current.distanceMeters = $0 }
                        ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                        TextField("Instruction", text: Binding(
                            get: { state.navigation.current.primaryText },
                            set: { state.navigation.current.primaryText = $0 }
                        )).textFieldStyle(.roundedBorder)
                        TextField("Street", text: Binding(
                            get: { state.navigation.current.streetName },
                            set: { state.navigation.current.streetName = $0 }
                        )).textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Navigation ON") { state.navigation.navigationOn() }.buttonStyle(.borderedProminent)
                            Button("Send Maneuver") { state.navigation.sendCurrent() }.buttonStyle(.bordered)
                        }
                        Button("Navigation OFF", role: .destructive) { state.navigation.navigationOff() }
                    }
                }.padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Navigation")
        }
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
            Button("Install") { Task { await state.maintenance.installPreparedOverride() } }
        } message: {
            Text("Writes only the data/local override after complete ADB read-back verification; the stock system animation is untouched.")
        }
        .alert("Restore stock boot animation?", isPresented: $confirmBootRestore) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) { Task { await state.maintenance.restoreStockFallback() } }
        } message: {
            Text("Deletes only the custom data/local override.")
        }
        .alert("Reboot HUD now?", isPresented: $confirmHUDReboot) {
            Button("Cancel", role: .cancel) {}
            Button("Reboot", role: .destructive) { Task { await state.maintenance.rebootHUD() } }
        } message: {
            Text("Keep HUD power stable until startup completes.")
        }
    }

    private func distanceText(_ instruction: NavigationInstruction) -> String {
        let exact = instruction.displayDistanceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !exact.isEmpty {
            return exact
        }

        let meters = instruction.distanceMeters
        guard meters > 0 else { return "—" }

        // Manual/non-OCR instructions have no original display string, so use
        // a conventional imperial fallback.
        let feet = Int((Double(meters) * 3.28084).rounded())
        if feet >= 5280 {
            return String(format: "%.1f mi", Double(feet) / 5280.0)
        }
        return "\(feet) ft"
    }
}
