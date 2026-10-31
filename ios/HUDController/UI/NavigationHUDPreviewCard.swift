import SwiftUI
import Foundation
import UIKit

/// v90.35.3.11 road-test Map Mode + OBD/STA instrumentation control surface.
///
/// The preferred physical path keeps the iPhone on the Carlinkit AP, places the
/// HUD in stock KivicCast STA mode 6, and relays rendered 480x240 JPEG frames
/// through U2W v8.15.1 to the HUD with session-scoped STA/MJPEG recovery.
struct NavigationHUDPreviewCard: View {
    @Bindable var state: AppState
    @AppStorage("HUD.U2WHomeProbe.ssid") private var u2wSSID = HUDU2WAdapterWiFiCredentials.defaultSSID
    @AppStorage("HUD.U2WHomeProbe.password") private var u2wPassword = ""
    @FocusState private var editingAdapterWiFiField: AdapterWiFiField?

    private enum AdapterWiFiField: Hashable {
        case ssid, password
    }
    @State private var showMapCustomization = false
    @State private var selectedDesignerComponent: HudMapDesignerComponent = .map
    @State private var designerDragOrigin = CGSize.zero
    @State private var designerDragging = false
    @State private var pendingDesignerReset: DesignerResetAction?

    private enum DesignerResetAction: String, Identifiable {
        case selected, all, imported
        var id: String { rawValue }
        var label: String {
            switch self {
            case .selected: return "Reset selected position"
            case .all: return "Reset all component positions"
            case .imported: return "Restore pre-designer layout"
            }
        }
    }

    private let accent = HudTheme.accent

    var body: some View {
        HudCard {
            VStack(alignment: .leading, spacing: 14) {
                header

                HudMapModeCanvas(
                    snapshot: state.mapModePreviewSnapshot,
                    settings: state.mapModeSettings,
                    sourceMapImage: state.mapModePreviewSourceImage,
                    previewLanePlaceholder: false,
                    suppressCustomSpeedForNativeOBDProbe: false,
                    warningHiddenTarget: nil
                )
                .aspectRatio(2.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }

                presetQuickSwitch
                mapModeRelayControls

                DisclosureGroup(isExpanded: $showMapCustomization) {
                    VStack(alignment: .leading, spacing: 14) {
                        customizationSamplePreview
                        layoutDesignerControls
                        musicOverlayControls
                        mapAppearanceControls
                        mapCropControls
                        speedLimitSignControls
                        rightSideFineTuningControls
                        componentControls
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
        .confirmationDialog(
            "Change \(state.mapModeSettings.presetTitle(state.mapModeSettings.activePresetIndex))?",
            isPresented: Binding(
                get: { pendingDesignerReset != nil },
                set: { if !$0 { pendingDesignerReset = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingDesignerReset {
                Button(action.label, role: .destructive) {
                    switch action {
                    case .selected:
                        state.mapModeSettings.resetDesignerOffset(selectedDesignerComponent)
                    case .all:
                        state.mapModeSettings.resetAllDesignerOffsets()
                    case .imported:
                        state.mapModeSettings.restoreImportedLayout()
                        selectedDesignerComponent = .map
                    }
                    pendingDesignerReset = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDesignerReset = nil }
        } message: {
            Text("This will change the active preset only. Its full previous layout will be saved for Undo Last Reset.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Custom Map Mode")
                    .font(.headline)
                Text("Customize the HUD map layout")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }


    private var presetQuickSwitch: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Map design presets", systemImage: "square.grid.3x1.below.line.grid.1x2")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("auto-saved")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Picker(
                "Map design preset",
                selection: Binding(
                    get: { state.mapModeSettings.activePresetIndex },
                    set: { state.mapModeSettings.selectPreset($0) }
                )
            ) {
                ForEach(0..<3, id: \.self) { index in
                    Text(state.mapModeSettings.presetTitle(index)).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .tint(accent)

            if state.mapModeSettings.activePresetIndex == 0 {
                Text("Your original layout is preserved.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var customizationSamplePreview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Style sample")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Demo • not live HUD output")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HudMapModeCanvas(
                snapshot: .customizationDemo,
                settings: state.mapModeSettings,
                sourceMapImage: nil,
                showsCustomizationSampleMap: true,
                previewLanePlaceholder: false,
                suppressCustomSpeedForNativeOBDProbe: false,
                warningHiddenTarget: nil
            )
            .aspectRatio(2.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }

            Text("Offline design preview; not the live map.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var layoutDesignerControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Map Mode layout designer")
                        .font(.subheadline.weight(.semibold))
                    Text("Select and drag a component")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(0..<3, id: \.self) { index in
                        if index != state.mapModeSettings.activePresetIndex {
                            Button("Copy into \(state.mapModeSettings.presetTitle(index))") {
                                state.mapModeSettings.duplicateCurrentPreset(to: index)
                            }
                        }
                    }
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(designerComponents) { component in
                    Button {
                        selectedDesignerComponent = component
                        designerDragging = false
                    } label: {
                        Label(component.title, systemImage: component.systemImage)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .center)
                            .padding(.horizontal, 6)
                            .background(
                                selectedDesignerComponent == component
                                    ? accent.opacity(0.24)
                                    : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        selectedDesignerComponent == component
                                            ? accent.opacity(0.85)
                                            : Color.white.opacity(0.12),
                                        lineWidth: selectedDesignerComponent == component ? 1.2 : 0.8
                                    )
                            }
                            .foregroundStyle(
                                selectedDesignerComponent == component ? accent : Color.primary
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select \(component.title) Map Mode component")
                }
            }

            ZStack {
                HudMapModeCanvas(
                    snapshot: .customizationDemo,
                    settings: state.mapModeSettings,
                    sourceMapImage: nil,
                    showsCustomizationSampleMap: true,
                    previewLanePlaceholder: false,
                    suppressCustomSpeedForNativeOBDProbe: false
                )

                GeometryReader { proxy in
                    Canvas { context, size in
                        let gridColor = Color.white.opacity(0.13)
                        let guideColor = Color.white.opacity(0.22)
                        for fraction in [0.25, 0.50, 0.75] {
                            var v = Path()
                            v.move(to: CGPoint(x: size.width * CGFloat(fraction), y: 0))
                            v.addLine(to: CGPoint(x: size.width * CGFloat(fraction), y: size.height))
                            context.stroke(v, with: .color(gridColor), lineWidth: 0.6)
                        }
                        for fraction in [0.25, 0.50, 0.75] {
                            var h = Path()
                            h.move(to: CGPoint(x: 0, y: size.height * CGFloat(fraction)))
                            h.addLine(to: CGPoint(x: size.width, y: size.height * CGFloat(fraction)))
                            context.stroke(h, with: .color(gridColor), lineWidth: 0.6)
                        }
                        var centerV = Path()
                        centerV.move(to: CGPoint(x: size.width * 0.5, y: 0))
                        centerV.addLine(to: CGPoint(x: size.width * 0.5, y: size.height))
                        context.stroke(centerV, with: .color(guideColor), lineWidth: 1.0)
                        var centerH = Path()
                        centerH.move(to: CGPoint(x: 0, y: size.height * 0.5))
                        centerH.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                        context.stroke(centerH, with: .color(guideColor), lineWidth: 1.0)
                    }
                    .allowsHitTesting(false)

                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    if !designerDragging {
                                        let current = state.mapModeSettings.designerCanvasPosition(for: selectedDesignerComponent)
                                        designerDragOrigin = CGSize(width: CGFloat(current.x), height: CGFloat(current.y))
                                        designerDragging = true
                                    }
                                    let sx = 480.0 / max(1.0, Double(proxy.size.width))
                                    let sy = 240.0 / max(1.0, Double(proxy.size.height))
                                    let x = snapDesignerPixel(Double(designerDragOrigin.width) + Double(value.translation.width) * sx)
                                    let y = snapDesignerPixel(Double(designerDragOrigin.height) + Double(value.translation.height) * sy)
                                    state.mapModeSettings.setDesignerCanvasPosition(selectedDesignerComponent, x: x, y: y)
                                }
                                .onEnded { _ in
                                    designerDragging = false
                                }
                        )

                    VStack {
                        HStack {
                            Label("Move: \(selectedDesignerComponent.title)", systemImage: selectedDesignerComponent.systemImage)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.70), in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(7)
                    .allowsHitTesting(false)
                }
            }
            .aspectRatio(2.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(accent.opacity(0.45), lineWidth: 1)
            }

            let selectedOffset = state.mapModeSettings.designerCanvasPosition(for: selectedDesignerComponent)
            HStack(spacing: 8) {
                Label(
                    "x \(Int(selectedOffset.x)) / 480 • y \(Int(selectedOffset.y)) / 240",
                    systemImage: "move.3d"
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    adjustSelectedDesigner(dx: -2, dy: 0)
                } label: { Image(systemName: "arrow.left") }
                Button {
                    adjustSelectedDesigner(dx: 0, dy: -2)
                } label: { Image(systemName: "arrow.up") }
                Button {
                    adjustSelectedDesigner(dx: 0, dy: 2)
                } label: { Image(systemName: "arrow.down") }
                Button {
                    adjustSelectedDesigner(dx: 2, dy: 0)
                } label: { Image(systemName: "arrow.right") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if selectedDesignerComponent != .music {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(width: 18)
                Text("Selected size")
                    .font(.caption)
                    .frame(width: 86, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { state.mapModeSettings.designerScale(for: selectedDesignerComponent) },
                        set: { state.mapModeSettings.setDesignerScale(selectedDesignerComponent, value: $0) }
                    ),
                    in: designerScaleRange,
                    step: 0.05
                )
                .tint(accent)
                Text(String(format: "%.0f%%", state.mapModeSettings.designerScale(for: selectedDesignerComponent) * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            } else {
                Text("Set music text size and widths in Music Overlay below.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider().padding(.top, 12)
            VStack(alignment: .leading, spacing: 10) {
                Label("Layout reset tools", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                Text("Reset requires confirmation.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Reset selected position") { pendingDesignerReset = .selected }
                        .buttonStyle(.bordered)
                    Button("Reset all positions") { pendingDesignerReset = .all }
                        .buttonStyle(.bordered)
                }
                .font(.caption)

                HStack(spacing: 8) {
                    Button("Restore pre-designer layout") { pendingDesignerReset = .imported }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                .font(.caption)

                if state.mapModeSettings.resetUndoAvailable {
                    Button {
                        state.mapModeSettings.undoLastReset()
                    } label: {
                        Label("Undo last reset (\(state.mapModeSettings.presetTitle(state.mapModeSettings.activePresetIndex)))", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                    Text("Restore the last preset layout.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 6)

            Text("Positions are saved per preset.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var designerScaleRange: ClosedRange<Double> {
        switch selectedDesignerComponent {
        case .speed, .timeLeft: return 0.50...1.80
        case .speedLimit: return 0.80...2.00
        case .map: return 0.60...1.45
        case .turningStreet, .maneuver, .distance, .eta: return 0.60...1.60
        case .lanes: return 0.60...1.70
        case .music: return 1.0...1.0
        }
    }

    private func snapDesignerPixel(_ value: Double) -> Double {
        (value / 2.0).rounded() * 2.0
    }

    private func adjustSelectedDesigner(dx: Double, dy: Double) {
        let current = state.mapModeSettings.designerCanvasPosition(for: selectedDesignerComponent)
        state.mapModeSettings.setDesignerCanvasPosition(
            selectedDesignerComponent,
            x: snapDesignerPixel(current.x + dx),
            y: snapDesignerPixel(current.y + dy)
        )
    }

    private var designerComponents: [HudMapDesignerComponent] {
        HudMapDesignerComponent.allCases.filter {
            !(state.mapModeSettings.etaUsesLanePositionWhenNoLanes && $0 == .eta)
        }
    }


    private var mapModeRelayControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("CarPlay adapter Wi-Fi name", text: $u2wSSID)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($editingAdapterWiFiField, equals: .ssid)

            SecureField("CarPlay adapter Wi-Fi password", text: $u2wPassword)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($editingAdapterWiFiField, equals: .password)

            // @AppStorage shows a default SSID without necessarily persisting it.
            // Saving explicitly commits BOTH displayed values and retries Auto Map
            // Mode on the current BLE session, without toggling the preference.
            Button("Save adapter Wi-Fi & retry Map Mode") {
                state.saveMapModeAdapterWiFiCredentials(ssid: u2wSSID, password: u2wPassword)
            }
            .buttonStyle(.bordered)
            .tint(accent)

            Text(state.adapterWiFiCredentialsStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("Automatic Map Mode", isOn: Binding(
                get: { state.automaticMapModeEnabled },
                set: { state.setAutomaticMapModeEnabled($0, reason: "main-tab switch") }
            ))
            .tint(accent)

            Text(state.automaticMapModeEnabled
                 ? (state.hudU2WLiveRelayActive ? "On • current HUD session starting/active" : "On • waiting for HUD connection or startup")
                 : "Off • CarPlay navigation uses the standard HUD Navigation mode")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Daily controls only. Test buttons, decoder telemetry, the legacy
            // FPS picker and manual diagnostic ZIP capture are intentionally
            // absent from the main Map Mode card; app logging remains active.
            HStack {
                Text("Map stream")
                    .font(.caption)
                Spacer()
                Text(state.hudU2WLiveRelayActive ? state.mainVideo.transportPhase : "Not active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Prevent Auto-Lock during Map Mode",
                isOn: Binding(
                    get: { state.mapModeSettings.preventAutoLockWhileMapMode },
                    set: { state.setMapModePreventAutoLock($0) }
                )
            )
            .font(.caption)

        }
        .onChange(of: editingAdapterWiFiField) { previous, next in
            // Save on keyboard dismissal too; do not start mid-password entry.
            if previous != nil && next == nil {
                state.saveMapModeAdapterWiFiCredentials(ssid: u2wSSID, password: u2wPassword)
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
                Text("Follow source uses the CarPlay map appearance.")
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

            Text("Adjust horizontal and vertical edge fading.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("Crop is applied to all CarPlay video.")
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

            Text("Adjust sign height and numeral size.")
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

            Text("Position changes by 2 pixels.")
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
                Text("Navigation component styling")
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
                title: "Lane arrow thickness",
                value: Binding(
                    get: { state.mapModeSettings.laneArrowThickness },
                    set: { state.mapModeSettings.laneArrowThickness = $0 }
                ),
                range: 0.60...2.50,
                step: 0.10,
                format: { String(format: "%.2fx", $0) }
            )
            tuningSlider(
                icon: "arrowtriangle.up.fill",
                title: "Lane arrow head size",
                value: Binding(
                    get: { state.mapModeSettings.laneArrowHeadScale },
                    set: { state.mapModeSettings.laneArrowHeadScale = $0 }
                ),
                range: 0.80...1.80,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
            )
            tuningSlider(
                icon: "arrow.up.and.down",
                title: "Lane arrow body length",
                value: Binding(
                    get: { state.mapModeSettings.laneArrowBodyLength },
                    set: { state.mapModeSettings.laneArrowBodyLength = $0 }
                ),
                range: 0.55...1.00,
                step: 0.05,
                format: { String(format: "%.0f%%", $0 * 100) }
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

            Toggle("Show AM/PM in ETA", isOn: Binding(
                get: { state.mapModeSettings.showETAAMPM },
                set: { state.mapModeSettings.showETAAMPM = $0 }
            ))
            .font(.caption)

            Divider().opacity(0.35)

            Text("Move components in the layout designer.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private var musicOverlayControls: some View {
        let music = state.mapModeSettings
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Music Overlay", systemImage: "music.note")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Show", isOn: binding(\.showMusicOverlay))
                    .labelsHidden()
            }

            if music.showMusicOverlay {
                Picker("Layout", selection: binding(\.musicTwoLines)) {
                    Text("One line").tag(false)
                    Text("Two lines").tag(true)
                }
                .pickerStyle(.segmented)

                musicSettingSlider("First line width", value: binding(\.musicTitleWidth), range: 65...320, suffix: "px")
                musicSettingSlider("First line font", value: binding(\.musicTitleFontSize), range: 9...30, suffix: "pt")
                if music.musicTwoLines {
                    musicSettingSlider("Artist line width", value: binding(\.musicArtistWidth), range: 65...320, suffix: "px")
                    musicSettingSlider("Artist font", value: binding(\.musicArtistFontSize), range: 8...28, suffix: "pt")
                }

                musicSettingSlider("Marquee speed", value: binding(\.musicMarqueeSpeed), range: 8...60, suffix: "px/s")
                ColorPicker("Text and symbol color", selection: musicColorBinding(isProgress: false), supportsOpacity: false)
                    .font(.caption)

                Toggle("Playback progress", isOn: binding(\.musicShowProgress))
                    .font(.caption)
                if music.musicShowProgress {
                    musicSettingSlider("Bar thickness", value: binding(\.musicBarHeight), range: 2...10, suffix: "px")
                    ColorPicker("Progress color", selection: musicColorBinding(isProgress: true), supportsOpacity: false)
                        .font(.caption)
                    Text("The progress bar always matches the first line's width.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    selectedDesignerComponent = .music
                } label: {
                    Label("Select music in layout designer", systemImage: "hand.draw")
                }
                .buttonStyle(.bordered)
                .font(.caption)
                Text("Automatically hidden when playback stops or metadata becomes unavailable. A sample track is shown in the designer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func musicSettingSlider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.caption).frame(width: 104, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue)) \(suffix)")
                .font(.caption2.monospacedDigit())
                .frame(width: 54, alignment: .trailing)
        }
    }

    private func musicColorBinding(isProgress: Bool) -> Binding<Color> {
        Binding(
            get: {
                let music = state.mapModeSettings
                return Color(red: isProgress ? music.musicBarRed : music.musicTextRed,
                             green: isProgress ? music.musicBarGreen : music.musicTextGreen,
                             blue: isProgress ? music.musicBarBlue : music.musicTextBlue)
            },
            set: { selected in
                let resolved = UIColor(selected).resolvedColor(with: .current)
                var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
                guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                let music = state.mapModeSettings
                if isProgress {
                    music.musicBarRed = Double(red)
                    music.musicBarGreen = Double(green)
                    music.musicBarBlue = Double(blue)
                } else {
                    music.musicTextRed = Double(red)
                    music.musicTextGreen = Double(green)
                    music.musicTextBlue = Double(blue)
                }
            }
        )
    }

    private var componentControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Visible components")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 7) {
                componentToggle("Speed", binding(\.showSpeed))
                componentToggle("Speed limit sign", binding(\.showSpeedLimit))
                componentToggle("Map", binding(\.showMap))
                componentToggle("Turning street", binding(\.showTurningStreet))
                componentToggle("Turn maneuver", binding(\.showManeuver))
                componentToggle("Distance", binding(\.showDistance))
                componentToggle("Lane guidance", binding(\.showLaneGuidance))
                componentToggle("ETA", binding(\.showETA))
                componentToggle("Time left", binding(\.showTimeLeft))
                componentToggle("Music overlay", binding(\.showMusicOverlay))
            }

            Divider().opacity(0.35)

            Toggle("Use lane-guidance position for ETA when lanes are unavailable", isOn: Binding(
                get: { state.mapModeSettings.etaUsesLanePositionWhenNoLanes },
                set: { enabled in
                    state.mapModeSettings.etaUsesLanePositionWhenNoLanes = enabled
                    if enabled && selectedDesignerComponent == .eta {
                        selectedDesignerComponent = .lanes
                    }
                }
            ))
            .font(.caption)

            Text("ETA occupies the lane area when no lanes are displayed.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func componentToggle(_ title: String, _ value: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Toggle("", isOn: value).labelsHidden()
        }
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

/// Compact main-tab controls for Map Mode overspeed + approaching-turn warnings.
/// Both warnings share one configurable warning text color.
struct MapModeSpeedWarningCard: View {
    @Bindable var state: AppState

    var body: some View {
        HudCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "speedometer")
                        .foregroundStyle(HudTheme.accent)
                    Text("Map Mode Warnings")
                        .font(.headline)
                    Spacer()
                    Text(state.mapModeSpeedSourceSummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Toggle("Enable overspeed warning", isOn: Binding(
                    get: { state.mapModeSettings.speedWarningEnabled },
                    set: { state.mapModeSettings.speedWarningEnabled = $0 }
                ))

                if state.mapModeSettings.speedWarningEnabled {
                    Toggle("Change speed number color", isOn: Binding(
                        get: { state.mapModeSettings.speedWarningNumberColorEnabled },
                        set: { state.mapModeSettings.speedWarningNumberColorEnabled = $0 }
                    ))

                    Toggle("Highlight speed background", isOn: Binding(
                        get: { state.mapModeSettings.speedWarningBackgroundEnabled },
                        set: { state.mapModeSettings.speedWarningBackgroundEnabled = $0 }
                    ))
                    if state.mapModeSettings.speedWarningBackgroundEnabled {
                        ColorPicker("Speed background warning color", selection: backgroundColorBinding, supportsOpacity: false)
                        HStack {
                            Text("Background opacity")
                            Slider(value: Binding(
                                get: { state.mapModeSettings.speedWarningBackgroundOpacity },
                                set: { state.mapModeSettings.speedWarningBackgroundOpacity = $0 }
                            ), in: 0.15...1.0)
                            Text("\(Int((state.mapModeSettings.speedWarningBackgroundOpacity * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }

                Divider().opacity(0.35)

                Toggle("Turn distance warning", isOn: Binding(
                    get: { state.mapModeSettings.maneuverWarningEnabled },
                    set: { state.mapModeSettings.maneuverWarningEnabled = $0 }
                ))

                if state.mapModeSettings.maneuverWarningEnabled {
                    LabeledContent(
                        "Warning below",
                        value: "\(state.mapModeSettings.maneuverWarningThresholdFeet) ft"
                    )
                    Slider(
                        value: Binding(
                            get: { Double(state.mapModeSettings.maneuverWarningThresholdFeet) },
                            set: { state.mapModeSettings.maneuverWarningThresholdFeet = Int($0.rounded()) }
                        ),
                        in: 100...2000,
                        step: 50
                    )
                }

                if state.mapModeSettings.maneuverWarningEnabled ||
                    (state.mapModeSettings.speedWarningEnabled && state.mapModeSettings.speedWarningNumberColorEnabled) {
                    ColorPicker("Warning text color", selection: numberColorBinding, supportsOpacity: false)
                }

                Text("Optional turn-distance and speed warning colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var numberColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(red: state.mapModeSettings.speedWarningNumberRed,
                      green: state.mapModeSettings.speedWarningNumberGreen,
                      blue: state.mapModeSettings.speedWarningNumberBlue)
            },
            set: { color in set(color: color, background: false) }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(red: state.mapModeSettings.speedWarningBackgroundRed,
                      green: state.mapModeSettings.speedWarningBackgroundGreen,
                      blue: state.mapModeSettings.speedWarningBackgroundBlue)
            },
            set: { color in set(color: color, background: true) }
        )
    }

    private func set(color: Color, background: Bool) {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
        if background {
            state.mapModeSettings.speedWarningBackgroundRed = Double(r)
            state.mapModeSettings.speedWarningBackgroundGreen = Double(g)
            state.mapModeSettings.speedWarningBackgroundBlue = Double(b)
        } else {
            state.mapModeSettings.speedWarningNumberRed = Double(r)
            state.mapModeSettings.speedWarningNumberGreen = Double(g)
            state.mapModeSettings.speedWarningNumberBlue = Double(b)
        }
        #endif
    }
}
