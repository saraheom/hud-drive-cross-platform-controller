import SwiftUI

struct NotificationSettingsCard: View {
    @Bindable var state: AppState

    var body: some View {
        HudCard {
            VStack(spacing: 0) {
                Text("ANCS NOTIFICATIONS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("All notification apps", isOn: Binding(
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
                    Label(
                        "Apply Notification Settings to HUD",
                        systemImage: "bell.and.waves.left.and.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 14)

                Text("""
                Verified on physical iPhone: Messages and KakaoTalk reach the HUD through the accessory notification path. Only apps that produce iOS Notification Center notifications belong in this section.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 10)

                Divider().padding(.vertical, 12)

                Text("MEDIA / NAVIGATION SOURCES")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                sourceRow(
                    "Spotify / Now Playing",
                    detail: "Separate media-accessory path; not ANCS"
                )
                sourceRow(
                    "Google Maps",
                    detail: "No turn guidance observed through ANCS"
                )
                sourceRow(
                    "Apple Maps",
                    detail: "No turn guidance observed through ANCS"
                )
                sourceRow(
                    "Waze",
                    detail: "No turn guidance observed through ANCS"
                )

                Text("""
                These sources stay in the architecture as separate future providers. They are intentionally not sent as ANCS application filters anymore.
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
        _ keyPath: ReferenceWritableKeyPath<HudSettings, Bool>
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { state.settings[keyPath: keyPath] },
            set: { state.settings[keyPath: keyPath] = $0 }
        ))
        .padding(.vertical, 8)
        Divider()
    }

    @ViewBuilder
    private func sourceRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        Divider()
    }
}
