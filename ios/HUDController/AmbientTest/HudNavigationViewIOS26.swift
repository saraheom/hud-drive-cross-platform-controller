#if AMBIENT_IOS26_TEST
import SwiftUI

// Navigation tab for the Xcode 26 build. ScreenCaptureKit/OCR controls and
// obsolete parked/manual diagnostic panels are intentionally omitted; live U2W
// route guidance and presentation settings remain available; device maintenance moved to Settings.
struct HudNavigationView: View {
    @Bindable var state: AppState
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

                            Text("Live U2W v8.8 active-event resolution remains unchanged. Center (stock) keeps the proven renderer. The two right-side choices are safe stock-widget probes for this field test.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recorded CarPlay lane replay")
                                .font(.headline)

                            Text("Parked diagnostic for the lane-placement probe. Replays real Apple Maps / Google Maps 0x5204 lane events through the same lane policy used by live U2W v8.8 guidance. Select a Right probe mode above to see whether the ETA region can render lanes without driving.")
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
                            .disabled(state.bluetooth.state != .connected)

                            HStack {
                                Button("◀ Previous") {
                                    let next = max(0, replayStepIndex - 1)
                                    replayStepIndex = next
                                    sendReplayStep(next)
                                }
                                .buttonStyle(.bordered)
                                .disabled(replayStepIndex == 0 || replayAutoRunning || state.bluetooth.state != .connected)

                                Button("Next ▶") {
                                    let next = min(replaySteps.count - 1, replayStepIndex + 1)
                                    replayStepIndex = next
                                    sendReplayStep(next)
                                }
                                .buttonStyle(.bordered)
                                .disabled(replayStepIndex >= replaySteps.count - 1 || replayAutoRunning || state.bluetooth.state != .connected)
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
                                .disabled(state.bluetooth.state != .connected)
                            }

                            Button("Clear Replayed Lanes") {
                                state.clearNativeLaneTest()
                            }
                            .buttonStyle(.bordered)
                            .disabled(state.bluetooth.state != .connected)

                            Text("For the quickest test, use Lane Guidance = Persistent and choose Right probe: Navigation or Right probe: NaviMini above. Each replay step turns Navigation on, sends the captured maneuver, then sends the captured lane topology through the same right-side probe state machine. No U2W adapter, ADB, or firmware write is involved.")
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
