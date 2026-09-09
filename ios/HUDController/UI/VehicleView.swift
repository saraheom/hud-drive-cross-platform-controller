import SwiftUI

struct VehicleView: View {
    @Bindable var state: AppState
    @State private var speedMarkerProbeLimitMph = 25

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

                            HudDescription("This uses the original app's HUD-managed OBD connection packets. Visible Freeride and Navigation side widgets are configured separately with the original HudWidgetCommandPacket (111/0).")
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

                            Speed engine and speed-limit sign settings are saved immediately and restored after app relaunch. Switching sources clears the previous sign until the selected matcher produces a fresh result. Speed warning follows the posted speed limit automatically. For a confirmed posted limit, the app now reasserts the original HUDWAY DisplaySpeedWarning threshold after Freeride/Navigation renderer changes. This is the stock DisplaySpeedWarning path used by HUDWAY Drive; v90.34.15 no longer assumes that packet alone owns the small red arc. The temporary probe below can reproduce the original Automatic/TRAVEL branch sequence without changing live speed-limit logic. Display-only/inferred limits remain intentionally ineligible for the native warning/marker.

                            Current keeps the decompiled HUDWAY matcher unchanged. OSM Trace preserves the rolling explicit-maxspeed matcher used in the latest road test for direct A/B comparison. Improved + Philly GIS loads nearby drivable OSM roads, strengthens road continuity, and inside Philadelphia cross-checks the City’s public Street Speed Limits and Residential Streets layers. Outside Philadelphia, the improved mode automatically continues with improved OSM only. Ambient-light overspeed warning controls now live entirely in the Ambient tab and consume this selected speed-limit result.
                            """)
                        }
                    }

                    section("SPEED MARKER PROBE — TEMPORARY") {
                        VStack(alignment: .leading, spacing: 12) {
                            Stepper(
                                "Test threshold: \(speedMarkerProbeLimitMph) mph",
                                value: $speedMarkerProbeLimitMph,
                                in: 5...100,
                                step: 5
                            )

                            Button("A — Exact original Automatic/TRAVEL sequence") {
                                state.speedEngine.runOriginalAutomaticMarkerProbe(
                                    limitMph: speedMarkerProbeLimitMph,
                                    restoreProductionSign: false
                                )
                            }
                            .buttonStyle(.borderedProminent)

                            Button("B — Original sequence + restore square sign") {
                                state.speedEngine.runOriginalAutomaticMarkerProbe(
                                    limitMph: speedMarkerProbeLimitMph,
                                    restoreProductionSign: true
                                )
                            }
                            .buttonStyle(.bordered)

                            Button("C — Current production sequence") {
                                state.speedEngine.runCurrentProductionMarkerProbe(
                                    limitMph: speedMarkerProbeLimitMph
                                )
                            }
                            .buttonStyle(.bordered)

                            Button("Restore live speed-limit state") {
                                state.speedEngine.restoreLiveSpeedLimitStateAfterMarkerProbe()
                            }
                            .buttonStyle(.bordered)

                            LabeledContent("Probe status", value: state.speedEngine.speedMarkerProbeStatus)

                            HudDescription("""
                            This block is diagnostic only. It does not change the selected speed-limit source, cached road limit, warning eligibility, or saved settings. A sends the decompiled HUDWAY Drive 1.4.6 Automatic/TRAVEL branch sequence exactly: HudSpeedLimitAndTolerance(limit=0, tolerance=0, style=0), followed by DisplaySpeedWarning(test threshold). B runs the same sequence, then restores our normal square speed-limit sign after 350 ms so we can see whether the native marker survives. C is the v90.34.14 production sequence for direct A/B comparison. Use Restore live speed-limit state when finished.
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
