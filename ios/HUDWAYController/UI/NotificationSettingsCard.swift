import SwiftUI

struct NotificationSettingsCard: View {
    @Bindable var settings: HudwaySettings

    var body: some View {
        HudCard {
            VStack(spacing: 0) {
                notificationToggle("Calls", $settings.notifyCalls)
                notificationToggle("Messages (SMS)", $settings.notifyMessages)
                notificationToggle("Calendar", $settings.notifyCalendar)
                notificationToggle("Gmail", $settings.notifyGmail)
                notificationToggle("WeChat", $settings.notifyWeChat)
                notificationToggle("KakaoTalk", $settings.notifyKakaoTalk)
                notificationToggle("Spotify", $settings.notifySpotify)

                Divider().padding(.vertical, 8)
                Stepper("Exposure time: \(settings.notificationExposureSeconds) sec",
                        value: $settings.notificationExposureSeconds, in: 2...30)
                Stepper("Lines of text: \(settings.notificationLines)",
                        value: $settings.notificationLines, in: 1...9)

                Text("Filtering UI is ready; the exact HUD/ANCS configuration packets are the next protocol item to validate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func notificationToggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(title, isOn: binding)
            .padding(.vertical, 8)
        Divider()
    }
}
