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

                                        Button("Re-authorize Spotify") {
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
                            Once authorized, Spotify credentials stay in Keychain. When HUD Controller returns to the foreground while disconnected, it creates a fresh Spotify App Remote, restores the saved token, and reconnects automatically. Failed connections retry after 1, 2, 5, 10, then every 15 seconds; repeated failures automatically replace the stale App Remote without erasing authorization.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Experimental HUD Music Layout")
                                .font(.title3.bold())

                            Text("""
                            Firmware experiment using the original app's hidden PushMessageCommandPacket. LEFT is the strongest candidate for a side region. The firmware exposes TOP, LEFT, DOWN, and FULL; no RIGHT position was found in this packet.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Picker(
                                "PushMessage position",
                                selection: Binding(
                                    get: { state.settings.experimentalMusicPosition },
                                    set: { state.settings.experimentalMusicPosition = $0 }
                                )
                            ) {
                                Text("Top").tag(0)
                                Text("Left").tag(1)
                                Text("Down").tag(2)
                                Text("Full").tag(3)
                            }
                            .pickerStyle(.segmented)

                            Toggle(
                                "Mirror Spotify track changes through PushMessage",
                                isOn: Binding(
                                    get: { state.settings.experimentalMusicMirror },
                                    set: { state.settings.experimentalMusicMirror = $0 }
                                )
                            )

                            Stepper(
                                "Message timeout: \(state.settings.experimentalMusicTimeout)s",
                                value: Binding(
                                    get: { state.settings.experimentalMusicTimeout },
                                    set: { state.settings.experimentalMusicTimeout = $0 }
                                ),
                                in: 1...3600,
                                step: state.settings.experimentalMusicTimeout < 60 ? 5 : 30
                            )

                            Stepper(
                                "Message lines: \(state.settings.experimentalMusicLines)",
                                value: Binding(
                                    get: { state.settings.experimentalMusicLines },
                                    set: { state.settings.experimentalMusicLines = $0 }
                                ),
                                in: 1...5
                            )

                            Toggle(
                                "Mini widgets state",
                                isOn: Binding(
                                    get: { state.settings.experimentalMusicMini },
                                    set: { state.settings.experimentalMusicMini = $0 }
                                )
                            )

                            HStack {
                                Button("Apply + Send Current Track") {
                                    state.sendExperimentalMusicPushMessage()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Clear") {
                                    state.clearExperimentalPushMessage()
                                }
                                .buttonStyle(.bordered)
                            }

                            Button("Apply Layout Controls Only") {
                                state.applyExperimentalMusicLayout()
                            }
                            .buttonStyle(.bordered)

                            Text("""
                            These commands are genuine firmware protocol commands found in the original Android library, but the production app did not expose this combination. Notification timeout may also affect other HUD notification renderers. Use this block as a controlled experiment rather than a confirmed dashboard widget.
                            """)
                            .font(.caption)
                            .foregroundStyle(.orange)
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
