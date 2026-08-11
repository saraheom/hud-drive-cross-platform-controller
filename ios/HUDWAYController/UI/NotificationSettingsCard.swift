import SwiftUI

struct NotificationSettingsCard: View {
    @Bindable var state: AppState

    var body: some View {
        HudCard {
            VStack(spacing: 0) {
                Toggle("All notifications", isOn: Binding(
                    get: { state.settings.notifyAll },
                    set: { state.settings.notifyAll = $0 }
                ))
                .padding(.vertical, 8)

                Divider()

                Group {
                    notificationToggle("Calls", \.notifyCalls)
                    notificationToggle("Messages (SMS / iMessage)", \.notifyMessages)
                    notificationToggle("Calendar", \.notifyCalendar)
                    notificationToggle("Gmail", \.notifyGmail)
                    notificationToggle("WeChat", \.notifyWeChat)
                    notificationToggle("KakaoTalk", \.notifyKakaoTalk)
                    notificationToggle("Spotify", \.notifySpotify)
                }
                .disabled(state.settings.notifyAll)

                Divider().padding(.vertical, 8)

                Text("MAP NOTIFICATION EXPERIMENT")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    notificationToggle("Google Maps", \.notifyGoogleMaps)
                    notificationToggle("Apple Maps", \.notifyAppleMaps)
                    notificationToggle("Waze", \.notifyWaze)
                }
                .disabled(state.settings.notifyAll)

                Divider().padding(.vertical, 8)

                Stepper(
                    "Exposure time: \(state.settings.notificationExposureSeconds) sec",
                    value: Binding(
                        get: { state.settings.notificationExposureSeconds },
                        set: { state.settings.notificationExposureSeconds = $0 }
                    ),
                    in: 2...30
                )

                Stepper(
                    "Lines of text: \(state.settings.notificationLines)",
                    value: Binding(
                        get: { state.settings.notificationLines },
                        set: { state.settings.notificationLines = $0 }
                    ),
                    in: 1...9
                )

                Button {
                    state.applyNotificationSettings()
                } label: {
                    Label("Apply Notification Settings to HUD",
                          systemImage: "bell.and.waves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 14)

                Text("""
                HUDWAY Drive itself receives iPhone notifications through ANCS. After pairing, open iOS Settings → Bluetooth → ⓘ next to HUDWAY Drive and enable “Share Notifications”. This app configures the HUD's notification filters; classic ANCS content is not exposed directly back to a normal iOS app.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func notificationToggle(
        _ title: String,
        _ keyPath: ReferenceWritableKeyPath<HudwaySettings, Bool>
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { state.settings[keyPath: keyPath] },
            set: { state.settings[keyPath: keyPath] = $0 }
        ))
        .padding(.vertical, 8)
        Divider()
    }
}
