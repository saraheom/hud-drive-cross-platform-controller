import SwiftUI

struct RootView: View {
    @Bindable var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: RootTab = .navigation

    var body: some View {
        TabView(selection: $selectedTab) {
            HudNavigationView(state: state)
                .tag(RootTab.navigation)
                .tabItem { Label("Navigation", systemImage: "location.north") }
            DashboardView(state: state)
                .tag(RootTab.dashboard)
                .tabItem { Label("Dashboard", systemImage: "rectangle.inset.filled") }
            MediaView(state: state)
                .tag(RootTab.media)
                .tabItem { Label("Media", systemImage: "music.note") }
            VehicleView(state: state)
                .tag(RootTab.vehicle)
                .tabItem { Label("Vehicle", systemImage: "car") }
            LogsView(state: state)
                .tag(RootTab.logs)
                .tabItem { Label("My trips", systemImage: "clock.arrow.circlepath") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if selectedTab != .logs {
                QuickShortcutBar(
                    navigationAction: {
                        selectedTab = .navigation
                        state.quickStartNavigation()
                    },
                    musicAction: {
                        selectedTab = .media
                        state.quickReconnectSpotify()
                    },
                    ambientAction: {
                        selectedTab = .vehicle
                        state.ambientLight.requestPairedLightsFocus()
                    }
                )
            }
        }
        .tint(HudTheme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            consumePendingShortcut()
            state.updateSpotifyVehicleWakeGate(reason: "root view appeared")
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
                // Refresh the vehicle evidence immediately before Spotify recovery.
                // Silent connect attempts may run anywhere, but app-switch/wake is
                // allowed only while HUD or OBD is actually connected.
                state.updateSpotifyVehicleWakeGate(reason: "app became active")
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

private enum RootTab: Hashable {
    case navigation
    case dashboard
    case media
    case vehicle
    case logs
}

private struct QuickShortcutBar: View {
    let navigationAction: () -> Void
    let musicAction: () -> Void
    let ambientAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            shortcut("Navigation", icon: "location.north.fill", action: navigationAction)
            shortcut("Music", icon: "music.note", action: musicAction)
            shortcut("Ambient", icon: "lightbulb.2.fill", action: ambientAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.6)
        }
    }

    private func shortcut(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 6)
            .background(HudTheme.card, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) shortcut")
    }
}
