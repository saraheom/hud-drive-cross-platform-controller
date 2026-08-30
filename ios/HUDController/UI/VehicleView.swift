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
                                    Text(source == .improvedTracePhilly ? "Improved + Philly" : source.rawValue).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(state.speedEngine.sourceMode.shortDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Speed engine and speed-limit sign settings are saved immediately and restored after app relaunch. Switching sources clears the previous sign until the selected matcher produces a fresh result. The HUD's native warning threshold still follows the posted limit exactly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()
                            Text("AMBIENT OVERSPEED WARNING")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle("Finite color-light warning", isOn: Binding(
                                get: { state.ambientLight.overspeedWarningEnabled },
                                set: { state.ambientLight.overspeedWarningEnabled = $0 }
                            ))

                            Picker("Warning light", selection: Binding(
                                get: { state.ambientLight.overspeedWarningLight },
                                set: { state.ambientLight.overspeedWarningLight = $0 }
                            )) {
                                ForEach(AmbientOverspeedWarningLight.allCases) { light in
                                    Text(light.rawValue).tag(light)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(!state.ambientLight.overspeedWarningEnabled)

                            ColorPicker(
                                "Warning color",
                                selection: Binding(
                                    get: { state.ambientLight.overspeedWarningColor.swiftUIColor },
                                    set: { state.ambientLight.setOverspeedWarningColor($0.ambientRGB) }
                                ),
                                supportsOpacity: false
                            )
                            .disabled(!state.ambientLight.overspeedWarningEnabled)

                            Stepper(
                                "Offset above limit: +\(state.ambientLight.overspeedWarningOffsetMph) mph",
                                value: Binding(
                                    get: { state.ambientLight.overspeedWarningOffsetMph },
                                    set: { state.ambientLight.setOverspeedWarningOffset($0) }
                                ),
                                in: 0...20
                            )
                            .disabled(!state.ambientLight.overspeedWarningEnabled)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Warning brightness: \(state.ambientLight.overspeedWarningBrightness)%")
                                    .font(.subheadline)
                                Slider(
                                    value: Binding(
                                        get: { Double(state.ambientLight.overspeedWarningBrightness) },
                                        set: { state.ambientLight.setOverspeedWarningBrightness(Int($0.rounded())) }
                                    ),
                                    in: 10...100,
                                    step: 5
                                )
                            }
                            .disabled(!state.ambientLight.overspeedWarningEnabled)

                            Picker("Pulse count", selection: Binding(
                                get: { state.ambientLight.overspeedWarningPulseCount },
                                set: { state.ambientLight.setOverspeedWarningPulseCount($0) }
                            )) {
                                Text("2×").tag(2)
                                Text("3×").tag(3)
                            }
                            .pickerStyle(.segmented)
                            .disabled(!state.ambientLight.overspeedWarningEnabled)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Pulse duration / cycle: \(state.ambientLight.overspeedWarningPulseDurationSeconds, specifier: "%.1f") s")
                                    .font(.subheadline)
                                Slider(
                                    value: Binding(
                                        get: { state.ambientLight.overspeedWarningPulseDurationSeconds },
                                        set: { state.ambientLight.setOverspeedWarningPulseDuration($0) }
                                    ),
                                    in: 0.0...5.0,
                                    step: 0.1
                                )
                            }
                            .disabled(!state.ambientLight.overspeedWarningEnabled)

                            LabeledContent("Repeat cooldown", value: "60 s")
                                .font(.subheadline)
                                .disabled(!state.ambientLight.overspeedWarningEnabled)

                            if state.speedEngine.speedLimitAvailableForWarning {
                                LabeledContent(
                                    "Warning threshold",
                                    value: "> \(state.speedEngine.currentSpeedLimitMph + state.ambientLight.overspeedWarningOffsetMph) mph"
                                )
                            } else if state.speedEngine.currentSpeedLimitMph > 0 {
                                LabeledContent("Warning threshold", value: "Displayed limit not warning-eligible — disabled")
                            } else {
                                LabeledContent("Warning threshold", value: "No speed-limit sign — disabled")
                            }

                            Text(state.ambientLight.overspeedWarningStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Triggers only when GPS speed crosses from at/below to strictly above posted speed limit + offset. It fires 2–3 finite pulses using your selected color, then restores the normal light state. After any warning starts, a 60-second cooldown suppresses threshold chatter even if speed repeatedly dips below and recrosses. If the speed-limit sign is unavailable, no warning is allowed. Dashboard warnings run only while the physical headlight circuit is on; headlight power loss cancels the warning without sending stale restore commands.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            LabeledContent("GPS speed", value: "\(state.speedEngine.currentSpeedMph) mph")
                            LabeledContent(
                                "Posted limit",
                                value: state.speedEngine.currentSpeedLimitMph > 0
                                    ? "\(state.speedEngine.currentSpeedLimitMph) mph\(state.speedEngine.speedLimitAvailableForWarning ? "" : " • warning off")"
                                    : "—"
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
                            Current keeps the decompiled HUDWAY matcher unchanged. OSM Trace preserves the rolling explicit-maxspeed matcher used in the latest road test for direct A/B comparison. Improved + Philly GIS loads all nearby drivable OSM roads, including neighborhood roads without maxspeed tags, clears stale signs after a short grace period, strengthens road continuity, and inside Philadelphia cross-checks the City’s public Street Speed Limits and Residential Streets layers. Outside Philadelphia, the improved mode automatically continues with improved OSM only. The ambient warning is suppressed unless the selected source has a fresh valid speed-limit result.
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
                            Toggle("Use Center/BLEDOM power for HUD Auto Brightness", isOn: Binding(
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
                            HUD Auto Brightness follows the fast Center/BLEDOM power signal, matching the earlier responsive behavior: Center present = night/Auto Brightness ON and Center absent = day/Auto Brightness OFF. Automatic Door day/night brightness consumes that same signal independently. Dashboard + Center are still recorded as a diagnostic cross-check, but Dashboard cannot delay either output. BLEDOM does not need to appear in Settings → Bluetooth.
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
