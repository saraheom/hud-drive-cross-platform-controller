import SwiftUI

struct VehicleView: View {
    @Bindable var state: AppState
    @State private var path: [VehicleRoute] = []
    @State private var handledAmbientShortcut = 0

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    section("OBD-II THROUGH HUD") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Auto-connect OBD after HUD connects", isOn: Binding(
                                get: { state.obd.autoConnect },
                                set: {
                                    state.obd.autoConnect = $0
                                    UserDefaults.standard.set($0, forKey: "HUD.OBD.autoConnect")
                                }
                            ))

                            TextField("OBD Bluetooth name", text: Binding(
                                get: { state.obd.deviceName },
                                set: { state.obd.deviceName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            HStack {
                                Button("Connect OBD") { state.obd.connect() }
                                    .buttonStyle(.borderedProminent)
                                Button("Disconnect") { state.obd.disconnect() }
                                    .buttonStyle(.bordered)
                            }

                            LabeledContent("Status", value: state.obd.status)
                            LabeledContent(
                                "Supported PIDs",
                                value: state.obd.supportedPIDs.isEmpty ? "—" : state.obd.supportedPIDs
                            )

                            Divider()
                            Text("Freeride HUD widgets").font(.headline)
                            Picker("Freeride left", selection: Binding(
                                get: { state.obd.freerideLeft },
                                set: { state.obd.freerideLeft = $0 }
                            )) {
                                ForEach(HudSideWidget.allCases) { Text($0.displayName).tag($0) }
                            }
                            Picker("Freeride right", selection: Binding(
                                get: { state.obd.freerideRight },
                                set: { state.obd.freerideRight = $0 }
                            )) {
                                ForEach(HudSideWidget.allCases) { Text($0.displayName).tag($0) }
                            }
                            Button("Apply Freeride Widgets") { state.obd.applyFreerideWidgets() }
                                .buttonStyle(.borderedProminent)

                            Divider()
                            Text("Navigation HUD widgets").font(.headline)
                            Picker("Navigation left", selection: Binding(
                                get: { state.obd.navigationLeft },
                                set: { state.obd.navigationLeft = $0 }
                            )) {
                                ForEach(HudSideWidget.allCases) { Text($0.displayName).tag($0) }
                            }
                            Picker("Navigation right", selection: Binding(
                                get: { state.obd.navigationRight },
                                set: { state.obd.navigationRight = $0 }
                            )) {
                                ForEach(HudSideWidget.allCases) { Text($0.displayName).tag($0) }
                            }
                            Button("Apply Navigation Widgets") { state.obd.applyNavigationWidgets() }
                                .buttonStyle(.borderedProminent)

                            Text("""
                            This uses the original app's HUD-managed OBD connection packets. Visible Freeride/Navigation side widgets are now configured separately with the original HudWidgetCommandPacket (111/0).
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    section("SPEED + SPEED LIMIT") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Speed + speed-limit engine", isOn: Binding(
                                get: { state.speedEngine.enabled },
                                set: { state.speedEngine.enabled = $0 }
                            ))

                            Toggle("Show speed-limit sign", isOn: Binding(
                                get: { state.speedEngine.showSpeedLimit },
                                set: { state.speedEngine.showSpeedLimit = $0 }
                            ))

                            Text("Speed-limit source")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Speed-limit source", selection: Binding(
                                get: { state.speedEngine.sourceMode },
                                set: { state.speedEngine.sourceMode = $0 }
                            )) {
                                ForEach(SpeedLimitSourceMode.allCases) { source in
                                    Text(source.rawValue).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(state.speedEngine.sourceMode.shortDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if state.speedEngine.sourceMode == .here {
                                VStack(alignment: .leading, spacing: 8) {
                                    SecureField(
                                        "HERE API key",
                                        text: Binding(
                                            get: { state.speedEngine.hereAPIKeyDraft },
                                            set: { state.speedEngine.hereAPIKeyDraft = $0 }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()

                                    HStack {
                                        Button("Save HERE Key") {
                                            state.speedEngine.saveHereAPIKey()
                                        }
                                        .buttonStyle(.borderedProminent)

                                        Button("Clear") {
                                            state.speedEngine.clearHereAPIKey()
                                        }
                                        .buttonStyle(.bordered)

                                        Spacer()

                                        Label(
                                            state.speedEngine.hereAPIKeyConfigured ? "Key saved" : "Not configured",
                                            systemImage: state.speedEngine.hereAPIKeyConfigured
                                                ? "checkmark.shield.fill" : "key.fill"
                                        )
                                        .font(.caption)
                                    }

                                    Text("The HERE key is stored in iPhone Keychain, not in the repository. HERE mode sends a short rolling GPS trace to HERE Route Matching and requests the applicable speed limit for the matched road.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text("Speed engine and speed-limit sign settings are saved immediately and restored after app relaunch. Switching sources clears the previous sign until the selected matcher produces a fresh result. The HUD's native warning threshold still follows the posted limit exactly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            LabeledContent("GPS speed", value: "\(state.speedEngine.currentSpeedMph) mph")
                            LabeledContent(
                                "Posted limit",
                                value: state.speedEngine.currentSpeedLimitMph > 0
                                    ? "\(state.speedEngine.currentSpeedLimitMph) mph" : "—"
                            )
                            LabeledContent("Source", value: state.speedEngine.sourceMode.rawValue)
                            Text(state.speedEngine.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Refresh selected source now") {
                                state.speedEngine.refreshNow()
                            }
                            .buttonStyle(.bordered)

                            Text("""
                            Current keeps the decompiled HUDWAY matcher unchanged. Enhanced OSM is a separate test path with directional maxspeed tags, a wider candidate search, and continuity confirmation to resist parallel-road/ramp jumps. HERE is an independent route-matching test source and requires your own HERE API key. GPS is still used only for the iPhone-side speed engine and map matching; the proposed ambient overspeed warning remains disabled until we can obtain the HUD/OBD vehicle speed directly.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    section("AMBIENT LIGHTING") {
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink(value: VehicleRoute.ambient(focusPairedLights: false)) {
                                HStack {
                                    Image(systemName: "lightbulb.2.fill")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Ambient Lighting Control")
                                            .font(.headline)
                                        Text("Paired lights, groups, presets, smooth brightness and power-up breath")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider()
                            Text("HUD AUTO-BRIGHTNESS TRIGGER")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Toggle("Use BLEDOM presence for HUD Auto Brightness", isOn: Binding(
                                get: { state.ambientLight.hudBrightnessTriggerEnabled },
                                set: { state.ambientLight.hudBrightnessTriggerEnabled = $0 }
                            ))
                            .disabled(!state.ambientLight.enabled)

                            TextField("BLE advertised name", text: Binding(
                                get: { state.ambientLight.targetName },
                                set: { state.ambientLight.targetName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Stepper(
                                "Absent timeout: \(state.ambientLight.absenceTimeoutSeconds)s",
                                value: Binding(
                                    get: { state.ambientLight.absenceTimeoutSeconds },
                                    set: { state.ambientLight.setAbsenceTimeout($0) }
                                ),
                                in: 1...30
                            )

                            LabeledContent("Status", value: state.ambientLight.status)
                            LabeledContent(
                                "Peripheral UUID",
                                value: state.ambientLight.detectedIdentifier.isEmpty
                                    ? "—" : state.ambientLight.detectedIdentifier
                            )
                            if let rssi = state.ambientLight.lastRSSI {
                                LabeledContent("RSSI", value: "\(rssi) dBm")
                            }

                            Text("""
                            The advertised-name field above selects only the light whose presence drives HUD Auto Brightness. Other paired ambient lights do not affect HUD brightness. BLEDOM does not need to appear in Settings → Bluetooth; the same CoreBluetooth manager now handles presence detection and direct ambient-light control. Absence is still confirmed after three timeout windows.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Vehicle")
            .navigationDestination(for: VehicleRoute.self) { route in
                switch route {
                case .ambient(let focusPairedLights):
                    AmbientLightingView(
                        monitor: state.ambientLight,
                        focusPairedLightsOnAppear: focusPairedLights
                    )
                }
            }
            .onAppear {
                let request = state.ambientLight.pairedLightsFocusRequest
                if request > 0, request != handledAmbientShortcut {
                    handledAmbientShortcut = request
                    path = [.ambient(focusPairedLights: true)]
                }
            }
            .onChange(of: state.ambientLight.pairedLightsFocusRequest) { _, request in
                guard request != handledAmbientShortcut else { return }
                handledAmbientShortcut = request
                path = [.ambient(focusPairedLights: true)]
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HudCard { content() }
        }
    }
}

private enum VehicleRoute: Hashable {
    case ambient(focusPairedLights: Bool)
}
