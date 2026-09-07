#if AMBIENT_IOS26_TEST
import SwiftUI

// Navigation tab for the Xcode 26 build. ScreenCaptureKit/OCR controls and
// parked/manual experimental panels are intentionally omitted. Live U2W route
// guidance and the stable presentation settings remain available.
struct HudNavigationView: View {
    @Bindable var state: AppState

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

                            Toggle("Show Current Turn Text", isOn: Binding(
                                get: { state.settings.navigationShowCurrentTurnText },
                                set: { value in
                                    state.settings.navigationShowCurrentTurnText = value
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

                            HudDescription("Persistent keeps the latest lane guidance visible for the current maneuver by reasserting the stock lane packet. Near Turn caches the lane data but displays it only inside the selected distance. Off clears lane graphics. Show Current Street controls the current-road line. Show Current Turn Text controls only the redundant language line such as ‘Turn right’, ‘Turn left’, or ‘U-turn’; the maneuver arrow, upcoming street name, distance, ETA, and route data remain unchanged.")
                        }
                    }
                }
                .padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Navigation")
        }
    }
}
#endif
