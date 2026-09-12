import SwiftUI

/// v90.35.3.5 custom Map Mode + live U2W relay IP-soft-connect/frame-resync control surface.
///
/// The preferred physical path keeps the iPhone on the Carlinkit AP, places the
/// HUD in stock KivicCast STA mode 6, and relays rendered 480x240 JPEG frames
/// through U2W v8.14.2 to the HUD with deterministic STA recovery.
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
                componentControls
                obdProbeControls

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "info.circle")
                    Text("U2W v8.11 exposes the real 800×480 CarPlay MainVideo stream. U2W v8.14.2 keeps live frame ingress and makes relay start idempotent: the iPhone renders this 480×240 custom HUD image, sends JPEG frames to 192.168.50.2:15331, and the HUD pulls the changing MJPEG stream from U2W while remaining in stock STA mode 6. The legacy mode-5 path below remains only for comparison.")
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

            Text("Requires U2W v8.14.2. Keep the iPhone connected to the Carlinkit/U2W Wi-Fi. v90.35.3.5 no longer erases the HUD's saved STA network before joining: it briefly returns to mode 4, enters mode 6, and overwrites NISSAN68 credentials non-destructively. A valid HUD DHCP address is treated as link-up even if this firmware reports status 6 / Empty network, so KivicCast discovery can still be forced. If the image is absent, use Retry HUD display rather than restarting the relay.")
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
