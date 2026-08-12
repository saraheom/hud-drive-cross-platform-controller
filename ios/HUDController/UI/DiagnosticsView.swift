import SwiftUI

struct DiagnosticsView: View {
    @Bindable var state: AppState

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("State", value: state.bluetooth.state.rawValue)
                LabeledContent("Device", value: state.bluetooth.connectedName ?? "None")
                LabeledContent("Last RX", value: state.bluetooth.lastRX.isEmpty ? "—" : state.bluetooth.lastRX)
                LabeledContent("ANCS authorized", value: state.bluetooth.ancsAuthorized ? "Yes" : "No")
                LabeledContent("Auto reconnect", value: state.bluetooth.reconnectStatus)
            }


            Section("ANCS / Notification diagnostics") {
                Text("HUD Drive consumes iPhone notifications directly through Apple's ANCS accessory service.")
                Text("The app now uses the normal HUD BLE connection and observes CoreBluetooth’s `ancsAuthorized` state. If iOS authorizes ANCS for the accessory, the log will record the authorization change.")
                    .font(.caption)
                Text("The app logs every notification-filter packet it sends. ANCS notification bodies will only appear in this app if HUD firmware independently forwards them back over the proprietary RX channel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Current session log") {
                if let url = state.logger.currentFileURL {
                    ShareLink(item: url) {
                        Label("Share current log", systemImage: "square.and.arrow.up")
                    }
                    Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                }
                Button("Clear visible log") { state.logger.clearVisibleEntries() }
            }

            Section("Live log") {
                ForEach(state.logger.entries.reversed()) { entry in
                    VStack(alignment: .leading) {
                        Text("[\(entry.category)] \(entry.message)")
                            .font(.caption.monospaced())
                        Text(entry.date.formatted(date: .omitted, time: .standard))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
    }
}
