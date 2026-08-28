import SwiftUI
import UIKit

struct AmbientLightingView: View {
    @Bindable var monitor: AmbientLightMonitor
    var focusPairedLightsOnAppear: Bool = false

    @State private var newGroupName = ""
    @State private var handledFocusRequest = -1
    @State private var doorDayDraft = 100.0
    @State private var doorNightDraft = 45.0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    section("AMBIENT LIGHTING") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable ambient-light Bluetooth", isOn: Binding(
                                get: { monitor.enabled },
                                set: { monitor.enabled = $0 }
                            ))

                            HStack {
                                statusDot(active: monitor.enabled)
                                Text(monitor.controllerStatus)
                                    .font(.subheadline)
                                Spacer()
                                Button("Scan") { monitor.scanNow() }
                                    .buttonStyle(.bordered)
                                    .disabled(!monitor.enabled)
                            }

                            Text("Background BLE scanning and reconnect remain active for the paired lights. The nearby-device list is hidden from the normal UI because the three vehicle lights are already configured.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    section("SMOOTH TRANSITIONS + BREATH") {
                        VStack(alignment: .leading, spacing: 14) {
                            valueSlider(
                                title: "Brightness transition",
                                value: Binding(
                                    get: { monitor.brightnessTransitionSeconds },
                                    set: { monitor.setBrightnessTransitionDuration($0) }
                                ),
                                range: 1.0...15.0,
                                step: 0.5,
                                suffix: "s"
                            )

                            Picker("Breath repeats", selection: Binding(
                                get: { monitor.breathCycles },
                                set: { monitor.setBreathCycles($0) }
                            )) {
                                Text("2×").tag(2)
                                Text("3×").tag(3)
                                Text("4×").tag(4)
                                Text("5×").tag(5)
                            }
                            .pickerStyle(.segmented)

                            valueSlider(
                                title: "Breath duration / cycle",
                                value: Binding(
                                    get: { monitor.breathDurationSeconds },
                                    set: { monitor.setBreathDuration($0) }
                                ),
                                range: 1.0...15.0,
                                step: 0.5,
                                suffix: "s"
                            )

                            Toggle("Synchronize nearby power-on Breaths", isOn: Binding(
                                get: { monitor.synchronizePowerOnBreathEnabled },
                                set: { monitor.synchronizePowerOnBreathEnabled = $0 }
                            ))

                            Button("Preview Enabled Lights") {
                                monitor.previewEnabledBreathNow()
                            }
                            .buttonStyle(.borderedProminent)

                            Text("Every controller return is treated as a fresh power-on event. BLEDIM Door/Dashboard wait briefly for firmware boot, then run Power ON → RGB → a complete Breath → preferred brightness. With synchronization OFF, each light owns its full animation independently. With it ON, lights that finish preparation within a 2.5 s grouping window share a timeline; late lights still get their own complete Breath.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    section("VEHICLE-AWARE LIGHTING") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Automatic Door day/night brightness", isOn: Binding(
                                get: { monitor.vehicleAutomationEnabled },
                                set: { monitor.vehicleAutomationEnabled = $0 }
                            ))

                            percentSlider(
                                title: "Door daytime brightness",
                                value: $doorDayDraft,
                                onEditingChanged: { editing in
                                    if !editing { monitor.setDoorDayBrightness(Int(doorDayDraft.rounded())) }
                                }
                            )
                            .disabled(!monitor.vehicleAutomationEnabled)

                            percentSlider(
                                title: "Door night brightness",
                                value: $doorNightDraft,
                                onEditingChanged: { editing in
                                    if !editing { monitor.setDoorNightBrightness(Int(doorNightDraft.rounded())) }
                                }
                            )
                            .disabled(!monitor.vehicleAutomationEnabled)

                            Text(monitor.doorBrightnessModeStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Door brightness is independent from animation and engine-session detection. Dashboard + Center both ON = night; both OFF = day; a mixed state preserves the last confirmed mode. That same stable two-light signal controls HUD Auto Brightness. Courtesy or reconnect events may still animate the individual lights, but they do not block Door day/night behavior.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    section("PAIRED LIGHTS") {
                        VStack(spacing: 10) {
                            if monitor.pairedDevices.isEmpty {
                                Text("No ambient lights are paired in this build.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(monitor.pairedDevices) { device in
                                    NavigationLink {
                                        AmbientDeviceControlView(monitor: monitor, deviceID: device.id)
                                    } label: {
                                        AmbientPairedDeviceRow(monitor: monitor, device: device)
                                    }
                                    .buttonStyle(.plain)
                                    if device.id != monitor.pairedDevices.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    .id("pairedLights")

                    section("LIGHT GROUPS") {
                        VStack(alignment: .leading, spacing: 12) {
                            if monitor.groups.isEmpty {
                                Text("Create a group to control multiple paired lights together.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(monitor.groups) { group in
                                NavigationLink {
                                    AmbientGroupControlView(monitor: monitor, groupID: group.id)
                                } label: {
                                    HStack {
                                        Image(systemName: "square.stack.3d.up")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.name).font(.headline)
                                            Text("\(group.memberIDs.count) light\(group.memberIDs.count == 1 ? "" : "s")")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            HStack {
                                TextField("New group name", text: $newGroupName)
                                    .textFieldStyle(.roundedBorder)
                                Button("Create") {
                                    monitor.createGroup(name: newGroupName)
                                    newGroupName = ""
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    section("PROTOCOL STATUS") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Lotus Lantern / ELK-BLEDOM: power, RGB and brightness control", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                            Label("BLEDIM2 / FFF1: official-iOS 55 AA power, RGB and brightness protocol", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Ambient Lighting")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                doorDayDraft = Double(monitor.doorDayBrightness)
                doorNightDraft = Double(monitor.doorNightBrightness)
                handledFocusRequest = monitor.pairedLightsFocusRequest
                if focusPairedLightsOnAppear {
                    scrollToPairedLights(proxy)
                }
            }
            .onChange(of: monitor.pairedLightsFocusRequest) { _, request in
                guard request != handledFocusRequest else { return }
                handledFocusRequest = request
                scrollToPairedLights(proxy)
            }
        }
    }

    private func scrollToPairedLights(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation { proxy.scrollTo("pairedLights", anchor: .top) }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HudCard { content() }
        }
    }

    @ViewBuilder
    private func valueSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f %@", value.wrappedValue, suffix))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private func percentSlider(
        title: String,
        value: Binding<Double>,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...100, step: 1, onEditingChanged: onEditingChanged)
        }
    }

    private func statusDot(active: Bool) -> some View {
        Circle()
            .fill(active ? Color.green : Color.secondary)
            .frame(width: 9, height: 9)
    }
}

private struct AmbientPairedDeviceRow: View {
    @Bindable var monitor: AmbientLightMonitor
    let device: AmbientLightDevice

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(monitor.isConnected(device.id) ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.headline)
                Text(device.role?.displayName ?? device.protocolKind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(monitor.connectionLabel(device.id))
                    .font(.caption)
                    .foregroundStyle(monitor.isConnected(device.id) ? Color.primary : Color.secondary)
            }

            Spacer()

            if let rssi = monitor.rssi(device.id) {
                Text("\(rssi)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct AmbientDeviceControlView: View {
    @Bindable var monitor: AmbientLightMonitor
    let deviceID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = Color.white
    @State private var brightness = 100.0
    @State private var rawBLEDIMHex = ""
    @State private var rawBLEDIMStatus = "Advanced diagnostic only — normal BLEDIM2 controls use the recovered official protocol."
    /// Prevent ColorPicker's programmatic onAppear synchronization from sending an
    /// unintended RGB command. This previously made merely opening a light page
    /// look like it "woke" a stranded controller and also consumed a BLEDIM
    /// write-without-response credit.
    @State private var colorPickerReady = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let device = monitor.pairedDevice(deviceID) {
                    section("DEVICE") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Circle()
                                    .fill(monitor.isConnected(deviceID) ? Color.green : Color.secondary)
                                    .frame(width: 10, height: 10)
                                Text(monitor.connectionLabel(deviceID))
                                Spacer()
                                if let rssi = monitor.rssi(deviceID) {
                                    Text("\(rssi) dBm")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack {
                                TextField("Device name", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") { monitor.renameDevice(deviceID, to: name) }
                                    .buttonStyle(.bordered)
                            }

                            Picker("Controller protocol", selection: Binding(
                                get: { monitor.pairedDevice(deviceID)?.protocolKind ?? .bledim2 },
                                set: { monitor.setProtocol(deviceID, to: $0) }
                            )) {
                                ForEach(AmbientLightProtocolKind.allCases) { kind in
                                    Text(kind.displayName).tag(kind)
                                }
                            }

                            Picker("Vehicle role", selection: Binding<AmbientLightRole?>(
                                get: { monitor.pairedDevice(deviceID)?.role },
                                set: { monitor.setRole(deviceID, to: $0) }
                            )) {
                                Text("Unassigned").tag(AmbientLightRole?.none)
                                ForEach(AmbientLightRole.allCases) { role in
                                    Text(role.displayName).tag(Optional(role))
                                }
                            }

                            Toggle("Auto-connect", isOn: Binding(
                                get: { monitor.pairedDevice(deviceID)?.autoConnect ?? false },
                                set: { monitor.setAutoConnect(deviceID, enabled: $0) }
                            ))

                            LabeledContent("Peripheral UUID", value: deviceID.uuidString)
                                .font(.caption)
                        }
                    }

                    section("LIGHT CONTROL") {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle("Power", isOn: Binding(
                                get: { monitor.pairedDevice(deviceID)?.powerOn ?? false },
                                set: { monitor.setPower(deviceID, on: $0) }
                            ))

                            ColorPicker("Color", selection: $color, supportsOpacity: false)
                                .onChange(of: color) { _, newColor in
                                    guard colorPickerReady else { return }
                                    monitor.setColor(deviceID, color: newColor.ambientRGB)
                                }

                            PresetColorRow(
                                presets: device.resolvedPresetColors,
                                onApply: { rgb in
                                    // Let the ColorPicker's single onChange path issue
                                    // the RGB command; do not double-send a preset tap.
                                    color = rgb.swiftUIColor
                                },
                                onSave: { slot in
                                    monitor.setDevicePresetColor(deviceID, slot: slot, color: color.ambientRGB)
                                }
                            )

                            HStack {
                                Text("Preferred brightness")
                                Spacer()
                                Text("\(Int(brightness))%")
                                    .monospacedDigit()
                            }
                            Slider(
                                value: $brightness,
                                in: 0...100,
                                step: 1,
                                onEditingChanged: { editing in
                                    if !editing {
                                        monitor.setBrightness(deviceID, percent: Int(brightness.rounded()))
                                    }
                                }
                            )

                            if let current = monitor.pairedDevice(deviceID)?.lastAppliedBrightness {
                                LabeledContent("Current / last applied", value: "\(current)%")
                                    .font(.caption)
                            }

                            Text("Manual brightness changes use the global \(String(format: "%.1f", monitor.brightnessTransitionSeconds)) s smooth transition instead of jumping directly to the target.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            if device.role == .door, monitor.vehicleAutomationEnabled {
                                Text("When the engine session is active, Door steady-state brightness follows the Day/Night targets on the main Ambient Lighting page. The generic preferred value remains saved for manual use.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    section("ANIMATION") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Animation on power-up", isOn: Binding(
                                get: { monitor.pairedDevice(deviceID)?.startupAnimationEnabled ?? false },
                                set: { monitor.setStartupAnimationEnabled(deviceID, enabled: $0) }
                            ))

                            Button("Preview Breath") {
                                monitor.previewStartupAnimation(deviceID)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!monitor.isControllable(deviceID))

                            Text("Global profile: \(monitor.breathCycles)× at \(String(format: "%.1f", monitor.breathDurationSeconds)) s per cycle (\(String(format: "%.1f", monitor.breathDurationSeconds * Double(monitor.breathCycles))) s total). Every cycle uses that light’s actual starting brightness: current → 0% → 100% → current, unless a new target is selected during the animation.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if device.protocolKind == .bledim2 {
                        section("BLEDIM DIAGNOSTICS") {
                            DisclosureGroup("FFF1 protocol / raw replay") {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("FFF0 → FFF1 • writeWithoutResponse + notify")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)

                                    Text(monitor.bledimAdvertisementSummary(deviceID))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    Text(monitor.bledimDeviceInfoSummary(deviceID))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    Button("Refresh Device Diagnostics") {
                                        monitor.refreshBLEDIMDiagnostics(deviceID)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!monitor.isConnected(deviceID))

                                    TextField("Raw FFF1 hex", text: $rawBLEDIMHex, axis: .vertical)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(2...4)

                                    Button("Send Packet to FFF1") {
                                        rawBLEDIMStatus = monitor.sendRawBLEDIMHex(deviceID, hex: rawBLEDIMHex)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(rawBLEDIMHex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !monitor.isBLEDIMRawTransportReady(deviceID))

                                    Text(rawBLEDIMStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 8)
                            }
                        }
                    }

                    if !monitor.groups.isEmpty {
                        section("GROUP MEMBERSHIP") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(monitor.groups) { group in
                                    Toggle(group.name, isOn: Binding(
                                        get: { monitor.group(group.id)?.memberIDs.contains(deviceID) ?? false },
                                        set: { monitor.setGroupMembership(groupID: group.id, deviceID: deviceID, included: $0) }
                                    ))
                                }
                            }
                        }
                    }

                    section("REMOVE") {
                        Button("Unpair Ambient Light", role: .destructive) {
                            monitor.unpair(deviceID)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("This ambient-light record is no longer available.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(HudTheme.background.ignoresSafeArea())
        .navigationTitle(monitor.pairedDevice(deviceID)?.displayName ?? "Ambient Light")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            colorPickerReady = false
            if let device = monitor.pairedDevice(deviceID) {
                name = device.displayName
                color = device.color.swiftUIColor
                brightness = Double(device.brightness)
            }
            // ColorPicker may publish the programmatic assignment on the next
            // render pass, so arm user-driven writes one main-loop turn later.
            DispatchQueue.main.async { colorPickerReady = true }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HudCard { content() }
        }
    }
}

struct AmbientGroupControlView: View {
    @Bindable var monitor: AmbientLightMonitor
    let groupID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = Color.white
    @State private var brightness = 100.0
    @State private var colorPickerReady = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let group = monitor.group(groupID) {
                    section("GROUP") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("Group name", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") { monitor.renameGroup(groupID, to: name) }
                                    .buttonStyle(.bordered)
                            }
                            Text("Group color and brightness commands are fanned out to every member. Brightness changes share one synchronized transition timeline.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    section("MEMBERS") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(monitor.pairedDevices) { device in
                                Toggle(isOn: Binding(
                                    get: { monitor.group(groupID)?.memberIDs.contains(device.id) ?? false },
                                    set: { monitor.setGroupMembership(groupID: groupID, deviceID: device.id, included: $0) }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.displayName)
                                        Text("\(device.protocolKind.displayName) • \(monitor.connectionLabel(device.id))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    section("GROUP CONTROL") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Button("Power On") { monitor.setGroupPower(groupID, on: true) }
                                    .buttonStyle(.borderedProminent)
                                Button("Power Off") { monitor.setGroupPower(groupID, on: false) }
                                    .buttonStyle(.bordered)
                            }
                            .disabled(group.memberIDs.isEmpty)

                            ColorPicker("Color", selection: $color, supportsOpacity: false)
                                .onChange(of: color) { _, newColor in
                                    guard colorPickerReady else { return }
                                    monitor.setGroupColor(groupID, color: newColor.ambientRGB)
                                }
                                .disabled(group.memberIDs.isEmpty)

                            PresetColorRow(
                                presets: group.resolvedPresetColors,
                                onApply: { rgb in
                                    color = rgb.swiftUIColor
                                },
                                onSave: { slot in
                                    monitor.setGroupPresetColor(groupID, slot: slot, color: color.ambientRGB)
                                }
                            )
                            .disabled(group.memberIDs.isEmpty)

                            HStack {
                                Text("Brightness")
                                Spacer()
                                Text("\(Int(brightness))%")
                                    .monospacedDigit()
                            }
                            Slider(
                                value: $brightness,
                                in: 0...100,
                                step: 1,
                                onEditingChanged: { editing in
                                    if !editing {
                                        monitor.setGroupBrightness(groupID, percent: Int(brightness.rounded()))
                                    }
                                }
                            )
                            .disabled(group.memberIDs.isEmpty)

                            Text("Tap a color block to apply it to the whole group. Tap the pencil under any slot to replace that preset with the current picker color.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    section("DELETE") {
                        Button("Delete Group", role: .destructive) {
                            monitor.deleteGroup(groupID)
                            dismiss()
                        }
                    }
                }
            }
            .padding()
        }
        .background(HudTheme.background.ignoresSafeArea())
        .navigationTitle(monitor.group(groupID)?.name ?? "Light Group")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            colorPickerReady = false
            name = monitor.group(groupID)?.name ?? ""
            if let firstID = monitor.group(groupID)?.memberIDs.first,
               let first = monitor.pairedDevice(firstID) {
                color = first.color.swiftUIColor
                brightness = Double(first.brightness)
            }
            DispatchQueue.main.async { colorPickerReady = true }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HudCard { content() }
        }
    }
}

private struct PresetColorRow: View {
    let presets: [AmbientRGB]
    let onApply: (AmbientRGB) -> Void
    let onSave: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    let rgb = index < presets.count ? presets[index] : AmbientRGB.defaultPresets[index]
                    VStack(spacing: 4) {
                        Button {
                            onApply(rgb)
                        } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(rgb.swiftUIColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.25), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onSave(index)
                            } label: {
                                Label("Replace preset \(index + 1) with current color", systemImage: "square.and.arrow.down")
                            }
                        }
                        .accessibilityLabel("Apply color preset \(index + 1)")

                        Button {
                            onSave(index)
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Replace color preset \(index + 1) with current picker color")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Tap a color block to apply • tap its pencil to save the current picker color into that slot")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

extension AmbientRGB {
    var swiftUIColor: Color {
        Color(
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0
        )
    }
}

extension Color {
    var ambientRGB: AmbientRGB {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return AmbientRGB(
                red: Int((red * 255).rounded()),
                green: Int((green * 255).rounded()),
                blue: Int((blue * 255).rounded())
            )
        }
        return .white
    }
}
