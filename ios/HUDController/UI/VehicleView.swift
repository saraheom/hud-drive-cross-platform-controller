import SwiftUI

struct VehicleView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
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
                            Music replaces Weather in this app. Internally it selects the HUD's original `Weather` side-widget token, which is a known valid dashboard slot. Spotify artist/track metadata is then sent through the native music path while this slot remains selected.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text("""
                            This uses the original app's HUD-managed OBD connection packets. Visible Freeride/Navigation side widgets are now configured separately with the original HudWidgetCommandPacket (111/0).
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    section("SPEED + SPEED LIMIT") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Original-style GPS / OSM speed engine", isOn: Binding(
                                get: { state.speedEngine.enabled },
                                set: { state.speedEngine.enabled = $0 }
                            ))

                            Toggle("Show speed-limit sign", isOn: Binding(
                                get: { state.speedEngine.showSpeedLimit },
                                set: { state.speedEngine.showSpeedLimit = $0 }
                            ))

                            Stepper(
                                "Warning tolerance: \(state.speedEngine.speedTolerance) mph",
                                value: Binding(
                                    get: { state.speedEngine.speedTolerance },
                                    set: { state.speedEngine.speedTolerance = $0 }
                                ),
                                in: 0...30
                            )

                            LabeledContent("GPS speed", value: "\(state.speedEngine.currentSpeedMph) mph")
                            LabeledContent(
                                "Posted limit",
                                value: state.speedEngine.currentSpeedLimitMph > 0
                                    ? "\(state.speedEngine.currentSpeedLimitMph) mph" : "—"
                            )
                            Text(state.speedEngine.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Refresh road data now") {
                                state.speedEngine.refreshNow()
                            }
                            .buttonStyle(.bordered)

                            Text("""
                            This follows the decompiled app's behavior: GPS supplies current speed; OpenStreetMap Overpass supplies nearby roads with maxspeed tags; the app chooses the closest heading-compatible segment and sends the firmware's native speed and speed-limit packets.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    section("AMBIENT LIGHT → HUD BRIGHTNESS") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Monitor ambient-light BLE device", isOn: Binding(
                                get: { state.ambientLight.enabled },
                                set: { state.ambientLight.enabled = $0 }
                            ))

                            TextField("BLE advertised name", text: Binding(
                                get: { state.ambientLight.targetName },
                                set: { state.ambientLight.targetName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Stepper(
                                "Absent timeout: \(state.ambientLight.absenceTimeoutSeconds)s",
                                value: Binding(
                                    get: { state.ambientLight.absenceTimeoutSeconds },
                                    set: { state.ambientLight.absenceTimeoutSeconds = $0 }
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
                            BLEDOM does not need to appear in Settings → Bluetooth. This monitor performs app-level BLE advertisement scanning, like Lotus Lantern. When BLEDOM is seen it sends HUD Auto Brightness ON; after the configured absence timeout it sends Auto Brightness OFF.
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
