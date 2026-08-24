import SwiftUI
import UIKit

struct AmbientLightingView: View {
    @Bindable var monitor: AmbientLightMonitor
    @State private var newGroupName = ""

    var body: some View {
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

                        Text("One CoreBluetooth manager handles all ambient lights and the existing BLEDOM → HUD Auto Brightness trigger. Paired lights reconnect automatically when available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                section("VEHICLE-AWARE LIGHTING") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Enable vehicle-aware startup / headlight automation", isOn: Binding(
                            get: { monitor.vehicleAutomationEnabled },
                            set: { monitor.vehicleAutomationEnabled = $0 }
                        ))

                        HStack(alignment: .top) {
                            Image(systemName: monitor.vehicleSessionActive ? "car.fill" : "car")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(monitor.vehicleAutomationStatus)
                                    .font(.subheadline)
                                Text("HUD power confirms engine ON. During a HUD-only outage, an independently observed OBD2 BLE advertisement keeps engine power ON. Automatic shutdown is inhibited until that OBD witness has been calibrated.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Circle()
                                .fill(monitor.enginePowerPresent ? Color.green : Color.secondary)
                                .frame(width: 9, height: 9)
                            Text(monitor.enginePowerStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "wave.3.right")
                                .foregroundStyle(.secondary)
                            Text(monitor.independentOBDWitnessStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("OBD witness calibration: while the engine remains running, switch only the physical HUD off once. If the OBD2 adapter is BLE and resumes advertising, HUD Controller learns its iOS UUID automatically. A later HUD thermal reboot will then be ignored while that OBD witness remains present.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Picker("Startup pulses", selection: Binding(
                            get: { monitor.vehicleStartupCycles },
                            set: { monitor.setVehicleStartupCycles($0) }
                        )) {
                            Text("1×").tag(1)
                            Text("2×").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .disabled(!monitor.vehicleAutomationEnabled)

                        valueSlider(
                            title: "Startup pulse duration",
                            value: Binding(
                                get: { monitor.vehicleStartupPulseDurationSeconds },
                                set: { monitor.setVehicleStartupPulseDuration($0) }
                            ),
                            range: 0.4...6.0,
                            step: 0.1,
                            suffix: "s"
                        )
                        .disabled(!monitor.vehicleAutomationEnabled)

                        valueSlider(
                            title: "Day/night classification window",
                            value: Binding(
                                get: { monitor.startupClassificationSeconds },
                                set: { monitor.setStartupClassificationDuration($0) }
                            ),
                            range: 1.0...8.0,
                            step: 0.5,
                            suffix: "s"
                        )
                        .disabled(!monitor.vehicleAutomationEnabled)

                        valueSlider(
                            title: "Headlight join fade",
                            value: Binding(
                                get: { monitor.headlightJoinFadeSeconds },
                                set: { monitor.setHeadlightJoinFadeDuration($0) }
                            ),
                            range: 0.4...6.0,
                            step: 0.1,
                            suffix: "s"
                        )
                        .disabled(!monitor.vehicleAutomationEnabled)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Door day / night brightness")
                                .font(.subheadline.weight(.semibold))

                            percentSlider(
                                title: "Daytime",
                                value: Binding(
                                    get: { Double(monitor.doorDayBrightness) },
                                    set: { monitor.setDoorDayBrightness(Int($0.rounded())) }
                                )
                            )

                            percentSlider(
                                title: "Night",
                                value: Binding(
                                    get: { Double(monitor.doorNightBrightness) },
                                    set: { monitor.setDoorNightBrightness(Int($0.rounded())) }
                                )
                            )

                            Text(monitor.doorBrightnessModeStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Night is detected when either the Dashboard light or Center Console/BLEDOM light is powered. The door fades between these two targets using the Headlight join fade duration. Day returns only after both headlight-fed lights are absent.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .disabled(!monitor.vehicleAutomationEnabled)

                        valueSlider(
                            title: "Engine-off confirmation",
                            value: Binding(
                                get: { monitor.engineOffConfirmationSeconds },
                                set: { monitor.setEngineOffConfirmationDuration($0) }
                            ),
                            range: 0.5...8.0,
                            step: 0.5,
                            suffix: "s"
                        )
                        .disabled(!monitor.vehicleAutomationEnabled)

                        valueSlider(
                            title: "Shutdown fade",
                            value: Binding(
                                get: { monitor.shutdownFadeSeconds },
                                set: { monitor.setShutdownFadeDuration($0) }
                            ),
                            range: 0.4...10.0,
                            step: 0.1,
                            suffix: "s"
                        )
                        .disabled(!monitor.vehicleAutomationEnabled)

                        HStack {
                            Button("Preview Current Startup") {
                                monitor.previewVehicleStartupNow()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Fade Out Now") {
                                monitor.fadeOutForVehicleShutdown()
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(!monitor.vehicleAutomationEnabled)

                        Button("Restore Current Brightness Targets") {
                            monitor.restorePreferredBrightnessNow()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!monitor.vehicleAutomationEnabled)

                        Text("Safety rule: a HUD disconnect alone never means engine OFF. Automatic shutdown is allowed only after the independent OBD BLE witness has been calibrated, the HUD is absent, the OBD witness fails to appear after its acquisition window, and the engine-off confirmation delay also expires. If the OBD adapter is Bluetooth Classic and cannot be seen by iOS, automatic shutdown stays inhibited rather than risking a false fade; Fade Out Now remains available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                section("PAIRED LIGHTS") {
                    VStack(spacing: 10) {
                        if monitor.pairedDevices.isEmpty {
                            Text("No ambient lights paired yet. Enable scanning and add the nearby controllers below.")
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

                section("LIGHT GROUPS") {
                    VStack(alignment: .leading, spacing: 12) {
                        if monitor.groups.isEmpty {
                            Text("Groups let any subset of lights respond together. A light can belong to more than one group.")
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

                section("NEARBY BLE DEVICES") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The two BLEDIM2 controllers may appear without a useful Bluetooth name. Use RSSI and the UUID suffix to identify them one at a time. Turn one controller off temporarily if that makes identification easier.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !monitor.enabled {
                            Text("Enable ambient-light Bluetooth above to scan.")
                                .foregroundStyle(.secondary)
                        } else if unpairedNearby.isEmpty {
                            HStack {
                                ProgressView()
                                Text("Scanning…")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(unpairedNearby.prefix(20)) { device in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.displayName)
                                                .font(.headline)
                                            Text("RSSI \(device.rssi) dBm • …\(device.id.uuidString.suffix(8))")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Add") {
                                            monitor.pair(device)
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }

                                    Text("Suggested: \(monitor.inferredProtocol(for: device).displayName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !device.serviceUUIDs.isEmpty {
                                        Text("Advertised services: \(device.serviceUUIDs.joined(separator: ", "))")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                if device.id != unpairedNearby.prefix(20).last?.id { Divider() }
                            }
                        }
                    }
                }

                section("PROTOCOL STATUS") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Lotus Lantern / ELK-BLEDOM: full power, RGB and brightness control", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                        Label("BLEDIM2 / CB01: experimental FFF0/FFF1 power, RGB and brightness control", systemImage: "testtube.2")
                            .font(.subheadline)
                        Text("Your two BLEDIM controllers both exposed FFF0 → FFF1 (writeWithoutResponse + notify). v90 enables the common CB01/BLEDIM 9-byte command family on that exact path and logs every transmitted packet. This payload profile could not be extracted from the Jiagu-packed BLEDIM2 APK, so validate it while stationary before relying on automation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .background(HudTheme.background.ignoresSafeArea())
        .navigationTitle("Ambient Lighting")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var unpairedNearby: [AmbientDiscoveredDevice] {
        let paired = Set(monitor.pairedDevices.map(\.id))
        return monitor.discoveredDevices.filter { !paired.contains($0.id) }
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

    private func percentSlider(title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...100, step: 1)
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
                Text(device.protocolKind.displayName)
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

                            if let role = device.role {
                                Text(role.powerSourceDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Toggle("Auto-connect", isOn: Binding(
                                get: { monitor.pairedDevice(deviceID)?.autoConnect ?? false },
                                set: { monitor.setAutoConnect(deviceID, enabled: $0) }
                            ))

                            LabeledContent("Peripheral UUID", value: deviceID.uuidString)
                                .font(.caption)
                            Text(monitor.gattSummary(deviceID))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
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
                                    monitor.setColor(deviceID, color: newColor.ambientRGB)
                                }

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
                                        monitor.setBrightness(deviceID, percent: Int(brightness))
                                    }
                                }
                            )

                            if let current = monitor.pairedDevice(deviceID)?.lastAppliedBrightness {
                                LabeledContent("Last applied", value: "\(current)%")
                                    .font(.caption)
                            }

                            if device.role == .door, monitor.vehicleAutomationEnabled {
                                Text("Vehicle automation currently owns the Door steady-state brightness using the separate Daytime/Night targets on the main Ambient Lighting page. This preferred value remains available for manual control and does not get overwritten by automatic dimming.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if device.protocolKind == .bledim2 {
                                Label("Experimental CB01/BLEDIM profile on FFF0/FFF1", systemImage: "testtube.2")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            if !monitor.isControllable(deviceID) {
                                Text("Waiting for the controller's writable characteristic. Selections are saved locally and will be applied when control becomes ready.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    section("STARTUP ANIMATION") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Fade on/off when a fresh light session connects", isOn: Binding(
                                get: { monitor.pairedDevice(deviceID)?.startupAnimationEnabled ?? false },
                                set: { monitor.setStartupAnimationEnabled(deviceID, enabled: $0) }
                            ))

                            Picker("Fade pulses", selection: Binding(
                                get: { monitor.pairedDevice(deviceID)?.startupCycles ?? 1 },
                                set: { monitor.setStartupCycles(deviceID, cycles: $0) }
                            )) {
                                Text("1×").tag(1)
                                Text("2×").tag(2)
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                Text("Pulse duration")
                                Spacer()
                                Text(String(format: "%.1f s", monitor.pairedDevice(deviceID)?.startupDurationSeconds ?? 1.5))
                                    .monospacedDigit()
                            }
                            Slider(value: Binding(
                                get: { monitor.pairedDevice(deviceID)?.startupDurationSeconds ?? 1.5 },
                                set: { monitor.setStartupDuration(deviceID, seconds: $0) }
                            ), in: 0.4...5.0, step: 0.1)

                            Button("Preview Startup Animation") {
                                monitor.previewStartupAnimation(deviceID)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!monitor.isControllable(deviceID))

                            Text(monitor.vehicleAutomationEnabled
                                 ? "Vehicle-aware mode supersedes this per-device reconnect animation so day/night pulses stay synchronized. Use Preview Current Startup on the main Ambient Lighting page."
                                 : "A fresh session fades 0 → target → 0 once or twice, then fades back to the saved target brightness. A short BLE dropout does not replay the animation; the device must stay disconnected for 15 seconds first.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
            if let device = monitor.pairedDevice(deviceID) {
                name = device.displayName
                color = Color(
                    red: Double(device.color.red) / 255.0,
                    green: Double(device.color.green) / 255.0,
                    blue: Double(device.color.blue) / 255.0
                )
                brightness = Double(device.brightness)
            }
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
                            Text("Commands fan out independently to each member's protocol adapter. Devices can belong to multiple groups.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    section("MEMBERS") {
                        VStack(alignment: .leading, spacing: 10) {
                            if monitor.pairedDevices.isEmpty {
                                Text("Pair ambient lights first.")
                                    .foregroundStyle(.secondary)
                            }
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
                                    monitor.setGroupColor(groupID, color: newColor.ambientRGB)
                                }
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
                                        monitor.setGroupBrightness(groupID, percent: Int(brightness))
                                    }
                                }
                            )
                            .disabled(group.memberIDs.isEmpty)

                            let experimentalCount = group.memberIDs.filter {
                                monitor.pairedDevice($0)?.protocolKind == .bledim2
                            }.count
                            if experimentalCount > 0 {
                                Text("\(experimentalCount) BLEDIM2/CB01 member\(experimentalCount == 1 ? " uses" : "s use") the experimental FFF1 compatibility profile; every group TX is logged.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
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
        .onAppear { name = monitor.group(groupID)?.name ?? "" }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HudCard { content() }
        }
    }
}

private extension Color {
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
