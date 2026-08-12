import SwiftUI

struct DashboardView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    sectionTitle("HUD BRIGHTNESS")
                    HudCard {
                        Toggle("Auto", isOn: Binding(
                            get: { state.settings.autoBrightness },
                            set: { state.settings.autoBrightness = $0; state.applyBrightness() }
                        ))
                            .font(.headline)

                        if !state.settings.autoBrightness {
                            Slider(value: Binding(
                                get: { Double(state.settings.brightness) },
                                set: { state.settings.brightness = Int($0) }
                            ), in: 0...100, step: 1)
                            .tint(HudTheme.accent)
                            .onChange(of: state.settings.brightness) { _, _ in state.applyBrightness() }
                        }

                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("HUD light / auto-brightness raw")
                                Spacer()
                                Text(state.bluetooth.hudAmbientRawValue.map(String.init) ?? "—")
                                    .monospacedDigit()
                            }
                            Slider(
                                value: .constant(Double(state.bluetooth.hudAmbientRawValue ?? 0)),
                                in: 0...255
                            )
                            .disabled(true)
                            Text("Experimental raw firmware value (event 3/30/0). We will verify during physical light/dark testing before treating this as calibrated lux.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    sectionTitle("SET UP YOUR HUD VIEWS")
                    HudCard {
                        Toggle("Minimize widgets", isOn: Binding(
                            get: { state.settings.minimizeWidgets },
                            set: { state.settings.minimizeWidgets = $0 }
                        ))
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(state.settings.selectedPreset.name).font(.title3.bold())
                                Text("\(state.settings.selectedPreset.left) • \(state.settings.selectedPreset.center) • \(state.settings.selectedPreset.right)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu("Edit") {
                                ForEach(DashboardPreset.presets) { preset in
                                    Button(preset.name) {
                                        state.settings.selectedPreset = preset
                                        state.applyDashboardPreset()
                                    }
                                }
                            }
                        }
                    }

                    sectionTitle("TIME & WEATHER")
                    HudCard {
                        Toggle("Show bottom time/weather panel", isOn: Binding(
                            get: { state.settings.showTimeWeather },
                            set: { state.settings.showTimeWeather = $0; state.applyTimeWeather() }
                        ))
                    }

                    sectionTitle("NOTIFICATIONS TO DISPLAY ON HUD")
                    NotificationSettingsCard(state: state)

                    NavigationLink("Advanced / Diagnostics") {
                        DiagnosticsView(state: state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(HudTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
