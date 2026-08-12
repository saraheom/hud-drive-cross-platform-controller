import SwiftUI

struct MediaView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Spotify").font(.title3.bold())

                            LabeledContent("Status", value: state.spotify.status)
                            LabeledContent("Track", value: state.spotify.trackTitle)
                            LabeledContent(
                                "Artist",
                                value: state.spotify.artistName.isEmpty ? "—" : state.spotify.artistName
                            )

                            if !state.spotify.isConfigured {
                                Text("Spotify Client ID is not configured in this build.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            HStack {
                                Button("Connect / Re-authorize Spotify") {
                                    state.spotify.connectOrAuthorize()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Disconnect") {
                                    state.spotify.disconnect()
                                }
                                .buttonStyle(.bordered)
                            }

                            Divider()

                            Button("Send Native HUD Music Test") {
                                state.sendNativeMusicTest()
                            }
                            .buttonStyle(.borderedProminent)

                            Text("""
                            After the first authorization, HUD Controller stores the Spotify App Remote token in Keychain and reconnects automatically when the app becomes active. Manual authorization is only needed initially or if Spotify invalidates the saved authorization. Track changes use the HUD firmware's native MusicNotificationPacket directly over BLE.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("External Navigation")
                                .font(.headline)

                            Text("""
                            No in-app routing engine is included. Navigation remains intentionally external-only: Apple Maps, Google Maps, Waze, or another map app must remain the route source. Future work will focus only on extracting guidance from those separate apps and feeding it into the existing HUD maneuver pipeline.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(HudTheme.background.ignoresSafeArea())
            .navigationTitle("Media")
        }
    }
}
