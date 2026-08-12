import SwiftUI

struct LogsView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("Current session") {
                    if let url = state.logger.currentFileURL {
                        ShareLink(item: url) { Label("Share Current Log", systemImage: "square.and.arrow.up") }
                        Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Saved sessions") {
                    ForEach(state.logger.logFiles(), id: \.self) { url in
                        ShareLink(item: url) {
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent)
                                Text(url.path).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HudTheme.background)
            .navigationTitle("Trips & Logs")
        }
    }
}
