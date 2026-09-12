import SwiftUI

/// v90.35.3.8 custom Map Mode + live U2W relay layout-calibration control surface.
///
/// The preferred physical path keeps the iPhone on the Carlinkit AP, places the
/// HUD in stock KivicCast STA mode 6, and relays rendered 480x240 JPEG frames
/// through U2W v8.14.3 to the HUD with deterministic STA recovery.
struct NavigationHUDPreviewCard: View {
    @Bindable var state: AppState
    @AppStorage("HUD.U2WHomeProbe.ssid") private var u2wSSID = "NISSAN68"
    @AppStorage("HUD.U2WHomeProbe.password") private var u2wPassword = ""

    private let accent = HudTheme.accent

    var body: some View {
        HudCard {
            VStack(alignment: .leading, spacing: 14) {
                header

                HudMapModeCanvas(
                    snapshot: state.mapModePreviewSnapshot,
                    settings: state.mapModeSettings,
                    sourceMapImage: state.mapModePreviewSourceImage,
                    previewLanePlaceholder: true,
                    suppressCustomSpeedForNativeOBDProbe: false
                )
                .aspectRatio(2.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }

                liveSourceControls
                hudU2WSTAHomeDiagnostic
                physicalCastControls
                mapAppearanceControls
                mapCropControls
                sizeControls
                widgetPositionControls
                rightSideFineTuningControls
                componentControls
                obdProbeControls

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                    Text("U2W v8.11 exposes the real 800×480 CarPlay MainVideo stream. U2W v8.14.3 keeps live frame ingress and makes relay start idempotent: the iPhone renders this 480×240 custom HUD image, sends JPEG frames to 192.168.50.2:15331, and the HUD pulls the changing MJPEG stream from U2W while remaining in stock STA mode 6. The legacy mode-5 path below remains only for comparison.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Map Mode")
                    .font(.headline)
                Text("Left / center / right HUD-safe layout • 480×240 cast target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }


    private var liveSourceControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live U2W map source")
                        .font(.subheadline.weight(.semibold))
                    Text(state.mainVideo.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.mainVideo.connected ? "LIVE" : "OFFLINE")
                        .font(.caption.bold())
                        .foregroundStyle(state.mainVideo.connected ? .green : .secondary)
                    Text("\(state.mainVideo.frameCount) frames • \(state.mainVideo.sourceSize)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Button("Reconnect U2W video") {
                state.mainVideo.reconnect(reason: "Map Mode UI")
            }
            .buttonStyle(.bordered)

            Text("Requires U2W v8.11 MainVideo Live on 192.168.50.2. The live preview remains independent of ScreenCaptureKit/OCR.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var hudU2WSTAHomeDiagnostic: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live iPhone → U2W → HUD relay")
                        .font(.subheadline.weight(.semibold))
                    Text("Mode 6 • HUD and iPhone stay on the Carlinkit AP • 5 fps JPEG relay")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.hudU2WSTAConnected ? "CONNECTED" : "IDLE")
                    .font(.caption.bold())
                    .foregroundStyle(state.hudU2WSTAConnected ? .green : .secondary)
            }

            TextField("U2W / Carlinkit SSID", text: $u2wSSID)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("U2W / Carlinkit Wi-Fi password", text: $u2wPassword)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack(spacing: 8) {
                Button("Start live U2W relay") {
                    state.startHUDU2WSTAHomeProbe(ssid: u2wSSID, password: u2wPassword)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(state.hudU2WLiveRelayActive || u2wSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || u2wPassword.isEmpty)

                Button("Request status") {
                    state.requestHUDU2WSTAStatus()
                }
                .buttonStyle(.bordered)
            }

            Button("Retry HUD display") {
                state.retryHUDU2WKivicDisplay()
            }
            .buttonStyle(.bordered)
            .disabled(!state.hudU2WLiveRelayActive)

            Button("Stop relay + restore HUD", role: .destructive) {
                state.stopHUDU2WSTAHomeProbe()
            }
            .buttonStyle(.bordered)

            LabeledContent("HUD STA status", value: state.hudU2WSTAStatus)
            LabeledContent("HUD STA IP", value: state.hudU2WSTAAddress.isEmpty ? "Not reported by HUD" : state.hudU2WSTAAddress)
            LabeledContent("Frame ingress", value: state.hudU2WFrameRelay.status)
            LabeledContent("Frames sent", value: "\(state.hudU2WFrameRelay.sentFrameCount)")
            LabeledContent("Last JPEG", value: state.hudU2WFrameRelay.lastFrameBytes == 0 ? "—" : "\(state.hudU2WFrameRelay.lastFrameBytes) bytes")
            if !state.hudU2WSTAReason.isEmpty {
                LabeledContent("Reason", value: state.hudU2WSTAReason)
            }

            Text("Requires U2W v8.14.3. Keep the iPhone connected to the Carlinkit/U2W Wi-Fi. v90.35.3.8 preserves the proven v90.35.3.7 start sequence: mode 6 once, credentials once, then wait. The layout controls below change only the 480×240 rendered JPEG and do not alter the relay transport.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var physicalCastControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Legacy mode-5 physical HUD test")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                if state.mapModeActive {
                    Button("Disable Map Mode") {
                        state.disableMapMode()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("Enable Map Mode on HUD") {
                        state.enableMapMode()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(state.hudU2WLiveRelayActive)
                }

                Spacer(minLength: 8)

                Text(state.mapModeActive ? "ON" : "OFF")
                    .font(.caption.bold())
                    .foregroundStyle(state.mapModeActive ? .green : .secondary)
            }

            Text(state.mapModeStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.hudU2WLiveRelayActive {
                Text("Disabled while the live U2W relay is active. Mode 5 would replace the HUD's mode-6 STA session and interrupt the relay.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if state.mapModeActive {
                Text("After the HUD AP starts, join HUDWAY Drive Wi-Fi on the iPhone. The app freezes the latest real U2W map frame plus route snapshot before Carlinkit becomes unreachable, then the HUD should discover the MJPEG stream automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var mapAppearanceControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Map appearance")
                .font(.subheadline.weight(.semibold))

            Picker(
                "Map appearance",
                selection: Binding(
                    get: { state.mapModeSettings.mapAppearance },
                    set: { state.mapModeSettings.mapAppearance = $0 }
                )
            ) {
                ForEach(HudMapAppearance.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(accent)

            if state.mapModeSettings.mapAppearance == .followSource {
                Text("Follow source preserves the actual Google Maps / Apple Maps / Waze light or dark appearance carried by MainVideo. Dark HUD and Light HUD are optional post-processing filters on those same pixels.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }


    private var mapCropControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Live map crop")
                .font(.subheadline.weight(.semibold))

            cropSlider(
                icon: "plus.magnifyingglass",
                title: "Map zoom",
                value: Binding(
                    get: { state.mapModeSettings.sourceMapZoom },
                    set: { state.mapModeSettings.sourceMapZoom = $0 }
                ),
                range: 0.80...2.60
            )
            cropSlider(
                icon: "arrow.left.and.right",
                title: "Crop X",
                value: Binding(
                    get: { state.mapModeSettings.sourceMapOffsetX },
                    set: { state.mapModeSettings.sourceMapOffsetX = $0 }
                ),
                range: -1.0...1.0
            )
            cropSlider(
                icon: "arrow.up.and.down",
                title: "Crop Y",
                value: Binding(
                    get: { state.mapModeSettings.sourceMapOffsetY },
                    set: { state.mapModeSettings.sourceMapOffsetY = $0 }
                ),
                range: -1.0...1.0
            )

            Text("Defaults are tuned from the 800×480 Google Maps frame recovered in your v8.10 dump. Adjust these while the live preview is connected if your current CarPlay layout differs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Independent widget size")
                .font(.subheadline.weight(.semibold))

            scaleSlider(
                icon: "speedometer",
                title: "Left widget",
                value: Binding(
                    get: { state.mapModeSettings.leftScale },
                    set: { state.mapModeSettings.leftScale = $0 }
                )
            )
            scaleSlider(
                icon: "map",
                title: "Center map",
                value: Binding(
                    get: { state.mapModeSettings.centerScale },
                    set: { state.mapModeSettings.centerScale = $0 }
                )
            )
            scaleSlider(
                icon: "arrow.turn.up.right",
                title: "Right widget",
                value: Binding(
                    get: { state.mapModeSettings.rightScale },
                    set: { state.mapModeSettings.rightScale = $0 }
                )
            )
        }
    }

    private var widgetPositionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Physical HUD position")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Reset all") {
                    state.mapModeSettings.resetWidgetOffsets()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            Text("Each arrow moves the selected 480×240 region by 2 pixels. Whole-widget movement is bounded to ±20 px horizontally and ±12 px vertically so a widget cannot be lost off-screen.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            positionPad(
                title: "Left widget",
                icon: "speedometer",
                x: \.leftOffsetX,
                y: \.leftOffsetY,
                xRange: -20...20,
                yRange: -12...12
            )
            positionPad(
                title: "Center map",
                icon: "map",
                x: \.centerOffsetX,
                y: \.centerOffsetY,
                xRange: -20...20,
                yRange: -12...12
            )
            positionPad(
                title: "Right widget",
                icon: "arrow.turn.up.right",
                x: \.rightOffsetX,
                y: \.rightOffsetY,
                xRange: -20...20,
                yRange: -12...12
            )
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var rightSideFineTuningControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Right-side maneuver / lane calibration")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Reset styling") {
                    state.mapModeSettings.resetRightStyling()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            tuningSlider(
                icon: "arrow.turn.up.right",
                title: "Turn arrow size",
                value: Binding(
                    get: { state.mapModeSettings.maneuverArrowScale },
                    set: { state.mapModeSettings.maneuverArrowScale = $0 }
                ),
                range: 0.80...1.40,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )
            tuningSlider(
                icon: "bold",
                title: "Turn arrow boldness",
                value: Binding(
                    get: { state.mapModeSettings.maneuverArrowThickness },
                    set: { state.mapModeSettings.maneuverArrowThickness = $0 }
                ),
                range: 1.00...2.50,
                step: 0.25,
                format: { String(format: "%.2fx", $0) }
            )
            tuningSlider(
                icon: "textformat.size",
                title: "Street text size",
                value: Binding(
                    get: { state.mapModeSettings.turningStreetScale },
                    set: { state.mapModeSettings.turningStreetScale = $0 }
                ),
                range: 0.80...1.30,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )
            tuningSlider(
                icon: "ruler",
                title: "Distance size",
                value: Binding(
                    get: { state.mapModeSettings.distanceScale },
                    set: { state.mapModeSettings.distanceScale = $0 }
                ),
                range: 0.80...1.30,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )

            Divider().opacity(0.35)

            tuningSlider(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Lane arrow size",
                value: Binding(
                    get: { state.mapModeSettings.laneScale },
                    set: { state.mapModeSettings.laneScale = $0 }
                ),
                range: 0.80...1.50,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )
            tuningSlider(
                icon: "bold",
                title: "Lane boldness",
                value: Binding(
                    get: { state.mapModeSettings.laneArrowThickness },
                    set: { state.mapModeSettings.laneArrowThickness = $0 }
                ),
                range: 1.00...2.50,
                step: 0.25,
                format: { String(format: "%.2fx", $0) }
            )
            tuningSlider(
                icon: "arrow.left.and.right",
                title: "Lane spacing",
                value: Binding(
                    get: { state.mapModeSettings.laneSpacing },
                    set: { state.mapModeSettings.laneSpacing = $0 }
                ),
                range: 1...8,
                step: 1,
                format: { "\(Int($0)) px" }
            )
            tuningSlider(
                icon: "sparkles",
                title: "Active lane emphasis",
                value: Binding(
                    get: { state.mapModeSettings.laneActiveEmphasis },
                    set: { state.mapModeSettings.laneActiveEmphasis = $0 }
                ),
                range: 1.00...1.35,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )

            Divider().opacity(0.35)

            tuningSlider(
                icon: "clock",
                title: "ETA / time-left size",
                value: Binding(
                    get: { state.mapModeSettings.etaScale },
                    set: { state.mapModeSettings.etaScale = $0 }
                ),
                range: 0.80...1.40,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )

            HStack {
                Text("Fine position")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset fine position") {
                    state.mapModeSettings.resetRightComponentOffsets()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
            }

            positionPad(
                title: "Turn arrow",
                icon: "arrow.turn.up.right",
                x: \.maneuverOffsetX,
                y: \.maneuverOffsetY,
                xRange: -12...12,
                yRange: -10...10
            )
            positionPad(
                title: "Lane guidance",
                icon: "arrow.triangle.branch",
                x: \.laneOffsetX,
                y: \.laneOffsetY,
                xRange: -12...12,
                yRange: -10...10
            )
            positionPad(
                title: "ETA / time left",
                icon: "clock",
                x: \.etaOffsetX,
                y: \.etaOffsetY,
                xRange: -12...12,
                yRange: -10...10
            )

            Text("Boldness maps to progressively heavier SF Symbol weights. All of these controls are persisted and are applied to both the on-phone preview and the live 480×240 JPEG sent to U2W.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var componentControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible components")
                .font(.subheadline.weight(.semibold))

            componentGroup("Left", rows: [
                ("Speed", binding(\.showSpeed)),
                ("Speed limit sign", binding(\.showSpeedLimit)),
            ])

            componentGroup("Center", rows: [
                ("Map", binding(\.showMap)),
            ])

            componentGroup("Right", rows: [
                ("Turning street", binding(\.showTurningStreet)),
                ("Turn maneuver", binding(\.showManeuver)),
                ("Distance", binding(\.showDistance)),
                ("Lane guidance", binding(\.showLaneGuidance)),
                ("ETA", binding(\.showETA)),
                ("Time left", binding(\.showTimeLeft)),
            ])
        }
    }

    private var obdProbeControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(
                "Native OBD speed overlay experiment",
                isOn: Binding(
                    get: { state.mapModeSettings.nativeOBDSpeedOverlayExperiment },
                    set: { state.mapModeSettings.nativeOBDSpeedOverlayExperiment = $0 }
                )
            )
            .tint(accent)

            Text("When ON and OBD is connected, the physical MJPEG frame intentionally leaves the custom speed number blank. After the HUD starts streaming, the app sends the recovered OBD_DRIVING_VELOCITY item (index 10) and re-opens the stock HUD layer. If a speed number appears there, it came from the HUD's true OBD path rather than GPS. The in-app preview still shows the speed for layout tuning.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }


    private func positionPad(
        title: String,
        icon: String,
        x: ReferenceWritableKeyPath<HudMapModeSettings, Double>,
        y: ReferenceWritableKeyPath<HudMapModeSettings, Double>,
        xRange: ClosedRange<Double>,
        yRange: ClosedRange<Double>
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("x \(Int(state.mapModeSettings[keyPath: x])) • y \(Int(state.mapModeSettings[keyPath: y]))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Spacer()
                nudgeButton("arrow.up", keyPath: y, delta: -2, range: yRange)
                Spacer()
            }
            HStack(spacing: 6) {
                nudgeButton("arrow.left", keyPath: x, delta: -2, range: xRange)
                Spacer()
                Button {
                    state.mapModeSettings[keyPath: x] = 0
                    state.mapModeSettings[keyPath: y] = 0
                } label: {
                    Image(systemName: "scope")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Center \(title)")
                Spacer()
                nudgeButton("arrow.right", keyPath: x, delta: 2, range: xRange)
            }
            HStack(spacing: 6) {
                Spacer()
                nudgeButton("arrow.down", keyPath: y, delta: 2, range: yRange)
                Spacer()
            }
        }
        .padding(8)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func nudgeButton(
        _ systemName: String,
        keyPath: ReferenceWritableKeyPath<HudMapModeSettings, Double>,
        delta: Double,
        range: ClosedRange<Double>
    ) -> some View {
        Button {
            let current = state.mapModeSettings[keyPath: keyPath]
            state.mapModeSettings[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, current + delta))
        } label: {
            Image(systemName: systemName)
                .frame(width: 22, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func tuningSlider(
        icon: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: (Double) -> String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
            Text(title)
                .font(.caption)
                .frame(width: 114, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(accent)
            Text(format(value.wrappedValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func cropSlider(
        icon: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .frame(width: 94, alignment: .leading)
            Slider(value: value, in: range, step: 0.02)
                .tint(accent)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func scaleSlider(icon: String, title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .frame(width: 94, alignment: .leading)
            Slider(value: value, in: 0.60...1.45, step: 0.05)
                .tint(accent)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func componentGroup(_ title: String, rows: [(String, Binding<Bool>)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Toggle(row.0, isOn: row.1)
                    .font(.subheadline)
                    .tint(accent)
            }
        }
        .padding(.vertical, 3)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<HudMapModeSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { state.mapModeSettings[keyPath: keyPath] },
            set: { state.mapModeSettings[keyPath: keyPath] = $0 }
        )
    }
}
