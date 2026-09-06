#if AMBIENT_IOS26_TEST
import SwiftUI

// Deliberately minimal Navigation tab for the temporary Xcode 26 build.
// Manual HUD navigation commands remain available for diagnostics, while all
// ScreenCaptureKit/OCR controls are removed from the compiled UI.
struct HudNavigationView: View {
    @Bindable var state: AppState
    @State private var lanePreset: AppState.NativeLaneTestPreset = .fourStraightUseThird
    @State private var replayRoute: RecordedCarPlayLaneReplay.Route = .appleMaps
    @State private var replayStepIndex = 0
    @State private var replayAutoRunning = false
    @State private var replayTask: Task<Void, Never>?

    private var replaySteps: [RecordedCarPlayLaneReplay.Step] { replayRoute.steps }

    private var currentReplayStep: RecordedCarPlayLaneReplay.Step {
        replaySteps[min(max(0, replayStepIndex), max(0, replaySteps.count - 1))]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    RouteGuidanceStatusCard(state: state)

                    HudCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Ambient-light test build", systemImage: "lightbulb.led")
                                .font(.headline)
                            Text("Automatic external-map screen capture is intentionally disabled in this Xcode 26 TestFlight build. HUD Bluetooth, vehicle controls, logging, and Ambient Lighting remain enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Navigation presentation")
                                .font(.headline)

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
                                ForEach(HudLaneGuidanceMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            if state.settings.laneGuidanceMode == .nearTurn {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(String(format: "Show lanes within %.1f mi (~%d ft)",
                                                state.settings.laneGuidanceDistanceMiles,
                                                Int((state.settings.laneGuidanceDistanceMiles * 5280).rounded())))
                                        .font(.subheadline)
                                    Slider(
                                        value: Binding(
                                            get: { state.settings.laneGuidanceDistanceMiles },
                                            set: { value in
                                                state.settings.laneGuidanceDistanceMiles = value
                                                state.applyNavigationPresentationSettings()
                                            }
                                        ),
                                        in: 0.1...1.0,
                                        step: 0.1
                                    )
                                }
                            }

                            Text("Persistent keeps the latest lane guidance visible for the maneuver by reasserting the stock lane packet. Near turn caches the lane data but displays it only inside the selected distance. Off clears lane graphics. Current Street controls only the current-road text; the upcoming road/maneuver stays available.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Live U2W v8.7 0x5204 lane arrays are enabled in this build. The Apple/Google recorded replay remains below for one final comparison test.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HUD Wi-Fi / casting network")
                                .font(.headline)

                            Toggle("Expose HUD Wi-Fi", isOn: Binding(
                                get: { state.hudWiFiExposureActive },
                                set: { enabled in
                                    if enabled { state.enableHUDWiFiExposure() }
                                    else { state.disableHUDWiFiExposure() }
                                }
                            ))
                            .disabled(state.bluetooth.state != .connected)

                            LabeledContent("Status", value: state.hudWiFiExposureStatus)
                            LabeledContent("Expected SSID", value: state.hudWiFiExpectedSSID)
                            LabeledContent("Password", value: "87654321")
                            LabeledContent("HUD IP", value: "192.168.43.1")

                            if state.hudWiFiExposureActive {
                                HStack {
                                    Button("Hold Cast Mode 5") {
                                        state.holdHUDWiFiCastingModeForDiagnostics()
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Return HUD Mode 4") {
                                        state.returnHUDRendererKeepingWiFi()
                                    }
                                    .buttonStyle(.bordered)
                                }
                                Text("Diagnostic fallback: if automatic exposure still gives a 169.254.x.x address, hold mode 5 and reconnect the laptop. If DHCP works there, Return HUD Mode 4 tests whether the AP survives while restoring native navigation/lane rendering.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("This reproduces only the HUD's stock 2.4-GHz Wi-Fi/AP exposure over BLE so your laptop can connect while this custom app remains open. It does not start iOS Screen Recording/Drive Broadcast, does not enter the software-update writer, and does not write HUD firmware.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Manual navigation diagnostics")
                                .font(.headline)

                            Picker("Maneuver", selection: Binding(
                                get: { state.navigation.current.maneuver },
                                set: { state.navigation.current.maneuver = $0 }
                            )) {
                                ForEach(HudManeuver.allCases) { maneuver in
                                    Text(maneuver.label).tag(maneuver)
                                }
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
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField("Street", text: Binding(
                                get: { state.navigation.current.streetName },
                                set: { state.navigation.current.streetName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            HStack {
                                Button("Navigation ON") { state.navigation.navigationOn() }
                                    .buttonStyle(.borderedProminent)
                                Button("Send Maneuver") { state.navigation.sendCurrent() }
                                    .buttonStyle(.bordered)
                            }

                            Button("Navigation OFF", role: .destructive) {
                                state.navigation.navigationOff()
                            }
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Firmware-native lane guidance")
                                .font(.headline)

                            Text("Diagnostic only. Sends the stock HudLanesManueverCommandPacket over the existing HUD BLE link; it does not modify the HUD firmware. Lane values use the firmware's signed active/inactive encoding.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Lane preset", selection: $lanePreset) {
                                ForEach(AppState.NativeLaneTestPreset.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }

                            HStack {
                                Button("Send Lane Test") {
                                    state.sendNativeLaneTest(lanePreset)
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Clear Lanes") {
                                    state.clearNativeLaneTest()
                                }
                                .buttonStyle(.bordered)
                            }

                            Text("For the clearest first test: turn Navigation ON, send a normal maneuver above, then send a lane preset. Positive lanes are the firmware's recommended/active lanes; negative lanes are dim/inactive.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recorded CarPlay lane replay")
                                .font(.headline)

                            Text("Parked diagnostic. Replays real 0x5204 lane-guidance messages recovered from earlier physical Apple Maps / Google Maps U2W captures, paired with the captured maneuver context. No adapter connection, OCR, ADB, or HUD firmware write is used.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Capture", selection: Binding(
                                get: { replayRoute },
                                set: { route in
                                    stopAutoReplay()
                                    replayRoute = route
                                    replayStepIndex = 0
                                }
                            )) {
                                ForEach(RecordedCarPlayLaneReplay.Route.allCases) { route in
                                    Text(route.title).tag(route)
                                }
                            }
                            .disabled(replayAutoRunning)

                            Text(replayRoute.captureLabel)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)

                            Divider()

                            Text("Step \(replayStepIndex + 1) of \(replaySteps.count) • \(currentReplayStep.displayTitle)")
                                .font(.subheadline.bold())

                            LabeledContent("Road", value: currentReplayStep.currentRoad)
                            LabeledContent("Maneuver", value: currentReplayStep.maneuverDescription)
                            LabeledContent("CP type", value: String(currentReplayStep.carPlayManeuverType))
                            LabeledContent("Distance", value: currentReplayStep.instruction.displayDistanceText)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Raw CarPlay lane angles")
                                    .font(.caption.bold())
                                Text(currentReplayStep.laneAngleSummary)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Native HUD signed values")
                                    .font(.caption.bold())
                                Text(currentReplayStep.hudValueSummary)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }

                            Button("Send This Recorded Step") {
                                sendReplayStep(replayStepIndex)
                            }
                            .buttonStyle(.borderedProminent)

                            HStack {
                                Button("◀ Previous") {
                                    let next = max(0, replayStepIndex - 1)
                                    replayStepIndex = next
                                    sendReplayStep(next)
                                }
                                .buttonStyle(.bordered)
                                .disabled(replayStepIndex == 0 || replayAutoRunning)

                                Button("Next ▶") {
                                    let next = min(replaySteps.count - 1, replayStepIndex + 1)
                                    replayStepIndex = next
                                    sendReplayStep(next)
                                }
                                .buttonStyle(.bordered)
                                .disabled(replayStepIndex >= replaySteps.count - 1 || replayAutoRunning)
                            }

                            if replayAutoRunning {
                                Button("Stop Auto Replay", role: .destructive) {
                                    stopAutoReplay()
                                }
                            } else {
                                Button("Auto Replay • 4 s/step") {
                                    startAutoReplay()
                                }
                                .buttonStyle(.bordered)
                            }

                            Button("Clear Replayed Lanes") {
                                state.clearNativeLaneTest()
                            }
                            .buttonStyle(.bordered)

                            Text("The replay uses the Navigation presentation settings above. Try Current Street ON/OFF and Lane Guidance Off/Near turn/Persistent; Persistent and eligible Near-turn lanes are reasserted every 1.5 seconds because the stock HUD can auto-hide the lane layer.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Navigation")
            .onDisappear { stopAutoReplay() }
        }
    }

    private func sendReplayStep(_ index: Int) {
        guard replaySteps.indices.contains(index) else { return }
        state.sendRecordedCarPlayLaneReplayStep(replaySteps[index])
    }

    private func startAutoReplay() {
        guard !replayAutoRunning else { return }
        replayAutoRunning = true
        let route = replayRoute
        let startIndex = replayStepIndex

        replayTask = Task { @MainActor in
            let steps = route.steps
            for index in startIndex..<steps.count {
                if Task.isCancelled { break }
                replayStepIndex = index
                state.sendRecordedCarPlayLaneReplayStep(steps[index])
                if index < steps.count - 1 {
                    try? await Task.sleep(for: .seconds(4))
                }
            }
            if !Task.isCancelled {
                replayAutoRunning = false
                replayTask = nil
            }
        }
    }

    private func stopAutoReplay() {
        replayTask?.cancel()
        replayTask = nil
        replayAutoRunning = false
    }
}
#endif
