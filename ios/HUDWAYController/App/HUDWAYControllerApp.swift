import SwiftUI

@main
struct HUDWAYControllerApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
        }
    }
}
