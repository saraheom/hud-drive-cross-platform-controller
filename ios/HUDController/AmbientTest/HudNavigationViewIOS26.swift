#if AMBIENT_IOS26_TEST
import SwiftUI

// Deliberately minimal Navigation tab for the temporary Xcode 26 build.
// Manual HUD navigation commands remain available for diagnostics, while all
// ScreenCaptureKit/OCR controls are removed from the compiled UI.
struct HudNavigationView: View {
    @Bindable var state: AppState
    @State private var lanePreset: AppState.NativeLaneTestPreset = .fourStraightUseThird

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
                }
                .padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Navigation")
        }
    }
}
#endif
