import SwiftUI
import UIKit

struct MediaView: View {
    @Bindable var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectionCard(state: state)

                    HudCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("CarPlay Now Playing").font(.title3.bold())
                                Spacer()
                                Button {
                                    state.nowPlaying.refreshNow()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }

                            HStack(alignment: .top, spacing: 16) {
                                artwork
                                    .frame(width: 112, height: 112)

                                VStack(alignment: .leading, spacing: 7) {
                                    Text(state.nowPlaying.title)
                                        .font(.headline)
                                        .lineLimit(2)
                                    Text(state.nowPlaying.artist.isEmpty ? "—" : state.nowPlaying.artist)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    if !state.nowPlaying.album.isEmpty {
                                        Text(state.nowPlaying.album)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            LabeledContent("Status", value: state.nowPlaying.status)
                            LabeledContent("Playback", value: state.nowPlaying.playbackDescription)
                            LabeledContent("Source", value: state.nowPlaying.sourceApp)
                            if !state.nowPlaying.sourceBundleID.isEmpty {
                                LabeledContent("Bundle", value: state.nowPlaying.sourceBundleID)
                                    .font(.caption)
                            }

                            if state.nowPlaying.durationMs > 0 {
                                ProgressView(
                                    value: min(Double(state.nowPlaying.elapsedMs), Double(state.nowPlaying.durationMs)),
                                    total: Double(state.nowPlaying.durationMs)
                                )
                                HStack {
                                    Text(formatTime(state.nowPlaying.elapsedMs))
                                    Spacer()
                                    Text(formatTime(state.nowPlaying.durationMs))
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }

                            if !state.nowPlaying.lastError.isEmpty {
                                Text(state.nowPlaying.lastError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Divider()

                            Button("Send Native HUD Music Test") {
                                state.sendNativeMusicTest()
                            }
                            .buttonStyle(.bordered)

                            Text("Media metadata now comes directly from the CarPlay adapter. Spotify authorization, tokens, callbacks, and automatic app launching are not used by this screen. Compatible active media apps can provide title, artist, album, playback state, progress, and artwork through CarPlay Now Playing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HudCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Physical HUD behavior").font(.headline)
                            Text("Track changes continue to use the HUD firmware's native transient Music notification packet. Persistent album/track widgets on the physical left/right dashboard remain limited by the HUD firmware's built-in widget set.")
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

    @ViewBuilder
    private var artwork: some View {
        if let data = state.nowPlaying.artworkData,
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func formatTime(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
