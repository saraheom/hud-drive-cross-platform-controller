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
                            Spotify metadata acquisition is working. The HUD currently does not visibly render MusicNotificationPacket, so the probe below tests other firmware text renderers before we bind Spotify to one permanently.
                            """)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Persistent Text / Music Probe")
                                .font(.title3.bold())

                            TextField("Title / artist", text: Binding(
                                get: { state.textProbe.title },
                                set: { state.textProbe.title = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField("Message / track", text: Binding(
                                get: { state.textProbe.message },
                                set: { state.textProbe.message = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            TextField("Package identifier", text: Binding(
                                get: { state.textProbe.packageName },
                                set: { state.textProbe.packageName = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                            Picker("Protocol route", selection: Binding(
                                get: { state.textProbe.selectedRoute },
                                set: { state.textProbe.selectedRoute = $0 }
                            )) {
                                ForEach(HudTextProbeRoute.allCases) { route in
                                    Text(route.displayName).tag(route)
                                }
                            }

                            if state.textProbe.selectedRoute == .genericNotification {
                                Stepper(
                                    "Notification category: \(state.textProbe.notificationCategory)",
                                    value: Binding(
                                        get: { state.textProbe.notificationCategory },
                                        set: { state.textProbe.notificationCategory = $0 }
                                    ),
                                    in: 0...31
                                )
                            }

                            HStack {
                                Button("Use Current Spotify") {
                                    state.textProbe.useCurrentSpotify(spotify: state.spotify)
                                }
                                .buttonStyle(.bordered)

                                Button("Send Selected Probe") {
                                    state.textProbe.sendSelected()
                                }
                                .buttonStyle(.borderedProminent)
                            }

                            Button("Sweep Notification Categories 0–15") {
                                state.textProbe.sweepNotificationCategories()
                            }
                            .buttonStyle(.bordered)

                            Button("Restore Normal Phone Name") {
                                state.textProbe.restoreNormalPhoneName()
                            }
                            .buttonStyle(.bordered)

                            LabeledContent("Probe status", value: state.textProbe.status)

                            Text("""
                            Goal: identify any HUD renderer that accepts arbitrary persistent text. Phone-name, notification, navigation, and raw dashboard-UTF paths are intentionally tested separately. Navigation text is already known to render persistently in the center; the key question is whether any other route can expose reusable text outside the navigation renderer.
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
