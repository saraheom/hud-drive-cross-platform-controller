import SwiftUI

struct HudNavigationView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    HudCard {
                        VStack(spacing: 14) {
                            Image(systemName: state.navigation.current.maneuver.symbol)
                                .font(.system(size: 64, weight: .semibold))
                            Text(state.navigation.current.primaryText).font(.title2.bold())
                            Text(state.navigation.current.streetName).font(.headline).foregroundStyle(.secondary)
                            Text(distanceText(state.navigation.current.distanceMeters))
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundStyle(HudTheme.accent)
                        }.frame(maxWidth: .infinity)
                    }

                    HudCard {
                        Picker("Maneuver", selection: Binding(
                            get: { state.navigation.current.maneuver },
                            set: { state.navigation.current.maneuver = $0 }
                        )) {
                            ForEach(HudManeuver.allCases) { m in Text(m.label).tag(m) }
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
                            Button("Navigation ON") { state.navigation.navigationOn() }.buttonStyle(.borderedProminent)
                            Button("Send Maneuver") { state.navigation.sendCurrent() }.buttonStyle(.bordered)
                        }
                        Button("Navigation OFF", role: .destructive) { state.navigation.navigationOff() }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Navigation pipeline").font(.headline)
                            Text("Manual / simulator source → NavigationInstruction → HUD packet encoder → serialized BLE transport")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(state.navigation.simulatorRunning ? "Simulator Running…" : "Start 5-Leg Simulator") {
                                    state.navigation.startSimulator()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(state.navigation.simulatorRunning)
                                Button("Stop") { state.navigation.stopSimulator() }.buttonStyle(.bordered)
                            }
                        }
                    }
                }.padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Navigation")
        }
    }

    private func distanceText(_ meters: Int) -> String {
        let feet = Int(Double(meters) * 3.28084)
        return "\(feet) ft"
    }
}
