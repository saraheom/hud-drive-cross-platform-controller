import SwiftUI
import Foundation

/// v90.35.3.11 road-test Map Mode + OBD/STA instrumentation control surface.
///
/// The preferred physical path keeps the iPhone on the Carlinkit AP, places the
/// HUD in stock KivicCast STA mode 6, and relays rendered 480x240 JPEG frames
/// through U2W v8.15.1 to the HUD with session-scoped STA/MJPEG recovery.
struct NavigationHUDPreviewCard: View {
    @Bindable var state: AppState
    @AppStorage("HUD.U2WHomeProbe.ssid") private var u2wSSID = "NISSAN68"
    @AppStorage("HUD.U2WHomeProbe.password") private var u2wPassword = ""
    @State private var showRelayDiagnostics = false
    @State private var showSTAPersistenceTest = false
    @State private var showMapCustomization = false

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

                mapModeRelayControls

                DisclosureGroup(isExpanded: $showMapCustomization) {
                    VStack(alignment: .leading, spacing: 14) {
                        mapAppearanceControls
                        mapCropControls
                        sizeControls
                        speedLimitSignControls
                        widgetPositionControls
                        rightSideFineTuningControls
                        componentControls
                        obdProbeControls
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Map Mode image customization", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(accent)
                .padding(10)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
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


    private var mapModeRelayControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("CarPlay adapter Wi-Fi name", text: $u2wSSID)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            SecureField("CarPlay adapter Wi-Fi password", text: $u2wPassword)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if state.hudU2WLiveRelayActive {
                Button("Disable Map Mode", role: .destructive) {
                    state.stopHUDU2WSTAHomeProbe()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Enable Map Mode") {
                    state.startHUDU2WSTAHomeProbe(ssid: u2wSSID, password: u2wPassword)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(
                    u2wSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    u2wPassword.isEmpty
                )
            }

            DisclosureGroup(isExpanded: $showRelayDiagnostics) {
                VStack(alignment: .leading, spacing: 7) {
                    LabeledContent("HUD STA status", value: state.hudU2WSTAStatus)
                    LabeledContent("HUD STA IP", value: state.hudU2WSTAAddress.isEmpty ? "Not reported by HUD" : state.hudU2WSTAAddress)
                    LabeledContent("MainVideo", value: state.mainVideo.status)
                    LabeledContent("Video frames", value: "\(state.mainVideo.frameCount) • \(state.mainVideo.sourceSize)")
                    LabeledContent("H.264 received", value: ByteCountFormatter.string(fromByteCount: state.mainVideo.receivedBytes, countStyle: .file))
                    LabeledContent("Frame ingress", value: state.hudU2WFrameRelay.status)
                    LabeledContent("Frames sent", value: "\(state.hudU2WFrameRelay.sentFrameCount)")
                    LabeledContent("HUD cadence", value: "5 fps • latest frame")
                    LabeledContent("Last JPEG", value: state.hudU2WFrameRelay.lastFrameBytes == 0 ? "—" : "\(state.hudU2WFrameRelay.lastFrameBytes) bytes")
                    if !state.hudU2WSTAReason.isEmpty {
                        LabeledContent("Reason", value: state.hudU2WSTAReason)
                    }

                    HStack(spacing: 8) {
                        Button("Request status") {
                            state.requestHUDU2WSTAStatus()
                        }
                        .buttonStyle(.bordered)

                        Button("Retry HUD display") {
                            state.retryHUDU2WKivicDisplay()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!state.hudU2WLiveRelayActive)
                    }

                    Button("Reconnect U2W video") {
                        state.mainVideo.reconnect(reason: "Map Mode UI")
                    }
                    .buttonStyle(.bordered)

                    DisclosureGroup(isExpanded: $showSTAPersistenceTest) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(state.hudSTAPersistenceTestStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Button("Test mode 6 → 4 STA persistence") {
                                state.runHUDMode4STAPersistenceTest()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!state.hudU2WLiveRelayActive || state.hudSTAPersistenceTestActive)

                            Button("Return Map Mode — mode 6 only") {
                                state.restoreHUDMode6AfterSTAPersistenceTest()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!state.hudU2WLiveRelayActive)

                            Text("Experimental road-test only. The first button leaves U2W/frame ingress running, sends HUD mode 4, then requests stock STA status at several checkpoints without clearing credentials. The second sends only mode 6—no SSID/password—to test whether an existing association can resume Map Mode immediately.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 5)
                    } label: {
                        Label("Mode 6 → 4 Wi-Fi association test", systemImage: "wifi.router")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(accent)
                }
                .font(.caption)
                .padding(.top, 6)
            } label: {
                Label("Status & diagnostics", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .tint(accent)
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
            Text("Live CarPlay crop")
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

            tuningSlider(
                icon: "arrow.left.and.right.circle",
                title: "Horizontal fade",
                value: Binding(
                    get: { state.mapModeSettings.mapFadeHorizontal },
                    set: { state.mapModeSettings.mapFadeHorizontal = $0 }
                ),
                range: 0.0...0.35,
                step: 0.01,
                format: { String(format: "%.0f%%", $0 * 100) }
            )
            tuningSlider(
                icon: "arrow.up.and.down.circle",
                title: "Vertical fade",
                value: Binding(
                    get: { state.mapModeSettings.mapFadeVertical },
                    set: { state.mapModeSettings.mapFadeVertical = $0 }
                ),
                range: 0.0...0.35,
                step: 0.01,
                format: { String(format: "%.0f%%", $0 * 100) }
            )

            Text("Fade controls adjust how far the center map dissolves into black from the horizontal and vertical edges. 0% disables that axis; larger values widen the fade boundary.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("The crop is intentionally content-blind: the exact same configured rectangle is taken from every live 800×480 CarPlay frame, whether the head unit is showing Dashboard, Google Maps, Apple Maps, Music, or another CarPlay screen.")
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


    private var speedLimitSignControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Speed-limit sign")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Reset") {
                    state.mapModeSettings.resetSpeedLimitStyling()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            tuningSlider(
                icon: "rectangle.compress.vertical",
                title: "Sign height",
                value: Binding(
                    get: { state.mapModeSettings.speedLimitSignHeightScale },
                    set: { state.mapModeSettings.speedLimitSignHeightScale = $0 }
                ),
                range: 0.80...2.00,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )
            tuningSlider(
                icon: "textformat.size",
                title: "Number font size",
                value: Binding(
                    get: { state.mapModeSettings.speedLimitFontScale },
                    set: { state.mapModeSettings.speedLimitFontScale = $0 }
                ),
                range: 0.70...1.60,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )

            Text("The sign width, white fill, black border, and black numeral remain fixed. Only vertical height and numeral size are adjustable.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
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
                Text("Right-side component size / spacing")
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
                range: 0.60...1.60,
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
                range: 0.60...1.60,
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
                range: 0.60...1.60,
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
                range: 0.60...1.70,
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
                icon: "circle.lefthalf.filled",
                title: "Inactive lane gray",
                value: Binding(
                    get: { state.mapModeSettings.laneInactiveGray },
                    set: { state.mapModeSettings.laneInactiveGray = $0 }
                ),
                range: 0.12...0.80,
                step: 0.04,
                format: { String(format: "%.0f%%", $0 * 100) }
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
                range: 0.60...1.60,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )

            Divider().opacity(0.35)

            Text("Vertical component spacing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            tuningSlider(
                icon: "arrow.up.and.down",
                title: "Street → maneuver",
                value: Binding(
                    get: { state.mapModeSettings.streetToManeuverSpacing },
                    set: { state.mapModeSettings.streetToManeuverSpacing = $0 }
                ),
                range: 0...20,
                step: 1,
                format: { "\(Int($0)) px" }
            )
            tuningSlider(
                icon: "arrow.up.and.down",
                title: "Maneuver → lanes",
                value: Binding(
                    get: { state.mapModeSettings.maneuverToLaneSpacing },
                    set: { state.mapModeSettings.maneuverToLaneSpacing = $0 }
                ),
                range: 0...20,
                step: 1,
                format: { "\(Int($0)) px" }
            )
            tuningSlider(
                icon: "arrow.up.and.down",
                title: "Lanes → ETA",
                value: Binding(
                    get: { state.mapModeSettings.laneToETASpacing },
                    set: { state.mapModeSettings.laneToETASpacing = $0 }
                ),
                range: 0...20,
                step: 1,
                format: { "\(Int($0)) px" }
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

            Text("Size, spacing, boldness, and fine-position controls are persisted and applied to both the on-phone preview and the live 480×240 JPEG sent to U2W.")
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
        VStack(alignment: .leading, spacing: 8) {
            Text("OBD speed road-test probe")
                .font(.subheadline.weight(.semibold))

            LabeledContent("HUD-side OBD", value: state.obd.connected ? "Connected" : "Not confirmed")
            LabeledContent("Visual probe", value: state.hudU2WNativeOBDProbeStatus)

            HStack(spacing: 8) {
                Button("Start 12s native OBD speed probe") {
                    state.startHUDU2WNativeOBDSpeedProbe()
                }
                .buttonStyle(.bordered)
                .disabled(!state.hudU2WLiveRelayActive || !state.obd.connected || state.hudU2WNativeOBDProbeActive)

                if state.hudU2WNativeOBDProbeActive {
                    Button("Stop", role: .destructive) {
                        state.stopHUDU2WNativeOBDSpeedProbe()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("Optional experiment for tomorrow's drive. For 12 seconds the iPhone-rendered GPS speed number is intentionally blank while the app asks for OBD_DRIVING_VELOCITY (item 10). The first 6 seconds leave the viewer/fullscreen state untouched; the second 6 seconds temporarily exposes the stock HUD layer. If a live speed number appears in that blank area, it is strong evidence that mode 6 can overlay the HUD's internally decoded OBD speed without sending that value back to iOS. The probe auto-restores the normal custom speed and does not re-send mode 6.")
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
