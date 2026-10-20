import SwiftUI

struct VehicleView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    section("MAP MODE OBD") {
                        VStack(alignment: .leading, spacing: 10) {
                            LabeledContent("Connection", value: state.directELM.ownershipStatus)
                            HudDescription("Map Mode now owns OBD from the iPhone automatically: it claims the remembered ELM327 and polls only standard 01 0D vehicle speed. Leaving Map Mode releases the iPhone connection before returning OBD ownership to the HUD. Detailed connection/probe telemetry is still recorded in diagnostics but is no longer shown here.")
                        }
                    }

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
                                Button("Connect via HUD") { state.obd.connect() }
                                    .buttonStyle(.borderedProminent)
                                Button("Disconnect HUD OBD") { state.obd.disconnect() }
                                    .buttonStyle(.bordered)
                            }

                            LabeledContent("HUD owns OBD", value: state.obd.connected ? "YES" : "NO")
                            LabeledContent("Status", value: state.obd.status)
                            HudDescription("Free Ride and Navigation use the HUD's OBD connection. Map Mode temporarily transfers the adapter to the phone and returns it when Map Mode ends.")

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
                            Button("Apply Freeride Widgets") {
                                state.obd.applyFreerideWidgets()
                                state.speedEngine.reassertOriginalSpeedMarker(reason: "Freeride widget profile applied")
                            }
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
                            Button("Apply Navigation Widgets") {
                                state.obd.applyNavigationWidgets()
                                state.speedEngine.reassertOriginalSpeedMarker(reason: "Navigation widget profile applied")
                            }
                                .buttonStyle(.borderedProminent)

                            HudDescription("Free Ride and Navigation widget layouts are saved separately and sent to the stock HUD.")
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

                            LabeledContent("GPS speed", value: "\(state.speedEngine.currentSpeedMph) mph")
                            LabeledContent(
                                "Posted limit",
                                value: state.speedEngine.currentSpeedLimitMph > 0
                                    ? "\(state.speedEngine.currentSpeedLimitMph) mph\(state.speedEngine.speedLimitAvailableForWarning ? "" : " • warning off")"
                                    : "—"
                            )
                            LabeledContent("Native speed marker", value: state.speedEngine.nativeSpeedMarkerStatus)
                            LabeledContent("Source", value: state.speedEngine.sourceMode.rawValue)
                            Text(state.speedEngine.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("Refresh selected source now") {
                                state.speedEngine.refreshNow()
                            }
                            .buttonStyle(.bordered)

                            HudDescription("""
                            \(state.speedEngine.sourceMode.shortDescription)

                            Speed engine and speed-limit sign settings are saved immediately and restored after app relaunch. Switching sources clears the previous sign until the selected matcher produces a fresh result. Speed warning follows the posted speed limit automatically. For a confirmed posted limit, the app now reasserts the original HUDWAY DisplaySpeedWarning threshold after Freeride/Navigation renderer changes. This is the stock DisplaySpeedWarning path used by HUDWAY Drive. Display-only/inferred limits remain intentionally ineligible for the native warning/marker.

                            Current keeps the decompiled HUDWAY matcher unchanged. OSM Trace preserves the rolling explicit-maxspeed matcher used in the latest road test for direct A/B comparison. Improved + Philly GIS loads nearby drivable OSM roads, strengthens road continuity, and inside Philadelphia cross-checks the City’s public Street Speed Limits and Residential Streets layers. Outside Philadelphia, the improved mode automatically continues with improved OSM only. Ambient-light overspeed warning controls now live entirely in the Ambient tab and consume this selected speed-limit result.
                            """)
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
