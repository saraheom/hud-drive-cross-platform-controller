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

                            Toggle("OBD speed protocol trace", isOn: Binding(
                                get: { state.bluetooth.obdSpeedTraceEnabled },
                                set: { state.bluetooth.obdSpeedTraceEnabled = $0 }
                            ))
                            LabeledContent("OBD trace", value: state.bluetooth.obdSpeedTraceStatus)
                            HudDescription("Road-test instrumentation only. This is passive: the iPhone does not connect to the OBD adapter and does not send extra PID requests. While enabled, the log annotates HUD→iPhone BLE frames as OBD TRACE / OBD TRACE RX and compares numeric payload candidates against simultaneous GPS mph/km/h.")

                            Divider()
                            Text("HUD OBD diagnostic capture").font(.headline)
                            LabeledContent("Diagnostic ZIP", value: state.bluetooth.obdDiagnosticStatus)
                            LabeledContent("Returned categories", value: state.bluetooth.obdDiagnosticObservedCategories)
                            HStack {
                                Button("Request latest HUD OBD logs") {
                                    state.bluetooth.requestOBDDiagnosticLogs(maxLastFilesCount: 2)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(state.bluetooth.state != .connected || state.bluetooth.obdDiagnosticTransferActive)

                                if state.bluetooth.obdDiagnosticTransferActive {
                                    Button("Stop & save raw") { state.bluetooth.cancelOBDDiagnosticLogs() }
                                        .buttonStyle(.bordered)
                                }
                            }
                            if let url = state.bluetooth.obdDiagnosticLogURL {
                                ShareLink(item: url) {
                                    Label("Share HUD OBD diagnostic ZIP", systemImage: "square.and.arrow.up")
                                }
                            }
                            if let url = state.bluetooth.obdDiagnosticRawCaptureURL {
                                ShareLink(item: url) {
                                    Label("Share raw HUD BLE capture", systemImage: "waveform.badge.magnifyingglass")
                                }
                            }
                            Button("Check whether HUD has stored OBD logs") {
                                state.bluetooth.requestRemainingDiagnosticLogTypes()
                            }
                            .buttonStyle(.bordered)
                            HudDescription("v90.35.3.13.2 keeps the bounded read-only LOG_CATEGORY_OBD forensic capture and hardens its framing. Only the three legal HUD escape pairs are accepted, immediate duplicate continuation notifications are suppressed for parsing while still preserved in the raw capture, and only exact-length diagnostic chunks are admitted to an archive. If the HUD returns LOG_CATEGORY_CRUSH instead of the requested OBD label, a structurally valid returned archive is now retained rather than discarded. If an archive still does not complete, tap Stop & save raw and share the .bin plus the normal HUD log. No second OBD connection or extra PID request is made by this capture.")

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
