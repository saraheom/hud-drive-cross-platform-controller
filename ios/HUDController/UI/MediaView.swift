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
                            LabeledContent(
                                "Authorization",
                                value: state.spotify.authorized ? "Saved" : "Required"
                            )
                            LabeledContent("Track", value: state.spotify.trackTitle)
                            LabeledContent(
                                "Artist",
                                value: state.spotify.artistName.isEmpty ? "—" : state.spotify.artistName
                            )

                            if !state.spotify.isConfigured {
                                Text("Spotify Client ID is not configured in this build.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            } else if state.spotify.authorizationRequired || !state.spotify.authorized {
                                Button("Authorize Spotify") {
                                    state.spotify.connectOrAuthorize()
                                }
                                .buttonStyle(.borderedProminent)

                                Text("Spotify authorization is required only the first time, or if Spotify later invalidates the saved authorization.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                HStack {
                                    if !state.spotify.connected {
                                        ProgressView()
                                        Text("Automatic reconnect is active")
                                            .font(.caption)
                                    } else {
                                        Label("Automatic connection active", systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                    }

                                    Spacer()

                                    Menu {
                                        Button("Reconnect Now") {
                                            state.spotify.connectOrAuthorize()
                                        }

                                        Button("Open Spotify / Resume Connection") {
                                            state.spotify.openSpotifyAndResumeConnection()
                                        }

                                        Button("Reset Spotify Authorization") {
                                            state.spotify.reauthorize()
                                        }

                                        Button("Disconnect Until App Reactivates") {
                                            state.spotify.disconnect()
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                    }
                                }
                            }

                            Divider()

                            Button("Send Native HUD Music Test") {
                                state.sendNativeMusicTest()
                            }
                            .buttonStyle(.bordered)

                            Text("""
                            Once authorized, Spotify credentials stay in Keychain. HUD Controller first reconnects silently; after repeated App Remote failures it now wakes Spotify automatically without clearing authorization, then reconnects when iOS returns to HUD Controller. Spotify may briefly appear if iOS had fully suspended it, but you should not need to keep Spotify open or press Reauthorize on normal drives. “Reset Spotify Authorization” is only for a genuinely revoked/invalid authorization.
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
