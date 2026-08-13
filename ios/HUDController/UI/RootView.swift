import SwiftUI

struct RootView: View {
    @Bindable var state: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            HudNavigationView(state: state)
                .tabItem { Label("Navigation", systemImage: "location.north") }
            DashboardView(state: state)
                .tabItem { Label("Dashboard", systemImage: "rectangle.inset.filled") }
            MediaView(state: state)
                .tabItem { Label("Media", systemImage: "music.note") }
            VehicleView(state: state)
                .tabItem { Label("Vehicle", systemImage: "car") }
            LogsView(state: state)
                .tabItem { Label("My trips", systemImage: "clock.arrow.circlepath") }
        }
        .tint(HudTheme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            consumePendingShortcut()
            state.spotify.autoConnectIfPossible()
        }
        .onOpenURL { url in
            if state.spotify.handleCallback(url) {
                state.logger.log("MEDIA", "Handled Spotify callback URL")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            state.logger.log("APP LIFECYCLE", "Scene phase \(String(describing: phase))")
            switch phase {
            case .active:
                consumePendingShortcut()
                state.spotify.appBecameActive()
                if #available(iOS 27.0, *),
                   let capture = state.externalCapture27 as? ExternalNavigationCapture {
                    capture.appBecameActive()
                }
            case .background:
                state.spotify.appEnteredBackground()
            default:
                break
            }
        }
    }

    private func consumePendingShortcut() {
        guard let raw = UserDefaults.standard.string(forKey: "pendingShortcutRequest"),
              let request = ShortcutRequest(rawValue: raw) else { return }
        UserDefaults.standard.removeObject(forKey: "pendingShortcutRequest")
        state.logger.log("SHORTCUT", "Executing \(raw)")
        switch request {
        case .initialize: state.initializeHUD()
        case .navigationOn: state.navigation.navigationOn()
        case .navigationOff: state.navigation.navigationOff()
        case .demoRoute: state.navigation.startSimulator()
        case .hideTimeWeather:
            state.settings.showTimeWeather = false
            state.applyTimeWeather()
        case .showTimeWeather:
            state.settings.showTimeWeather = true
            state.applyTimeWeather()
        case .connect:
            state.bluetooth.scan()
        }
    }
}
