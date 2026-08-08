import SwiftUI

struct ConnectionCard: View {
    let state: AppState
    @State private var selectedDeviceID: UUID?

    var selectedDevice: HudwayBluetoothManager.Device? {
        state.bluetooth.devices.first(where: { $0.id == selectedDeviceID })
    }

    var body: some View {
        HudCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("HUDWAY DRIVE").font(.caption).foregroundStyle(.secondary)
                        Text(state.bluetooth.connectedName ?? state.bluetooth.state.rawValue)
                            .font(.title3.bold())
                    }
                    Spacer()
                    Circle()
                        .fill(state.bluetooth.state == .connected ? HudTheme.accent : .gray)
                        .frame(width: 12, height: 12)
                }

                if state.bluetooth.state != .connected {
                    Picker("Device", selection: $selectedDeviceID) {
                        Text("Select HUD").tag(UUID?.none)
                        ForEach(state.bluetooth.devices) { device in
                            Text("\(device.name)  \(device.rssi) dBm").tag(Optional(device.id))
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        Button("Scan") { state.bluetooth.scan() }.buttonStyle(.borderedProminent)
                        Button("Connect") {
                            if let selectedDevice { state.bluetooth.connect(selectedDevice) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedDevice == nil)
                    }
                } else {
                    HStack {
                        Button("Initialize HUD") { state.initializeHUD() }.buttonStyle(.borderedProminent)
                        Button("Disconnect", role: .destructive) { state.bluetooth.disconnect() }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
