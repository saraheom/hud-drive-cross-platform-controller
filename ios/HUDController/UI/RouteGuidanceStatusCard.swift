import SwiftUI

struct RouteGuidanceStatusCard: View {
    @Bindable var state: AppState

    var body: some View {
        HudCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("CarPlay Route Guidance", systemImage: "car.front.waves.up")
                        .font(.headline)
                    Spacer()
                    Text(state.routeGuidance.running ? "LIVE" : "IDLE")
                        .font(.caption.bold())
                        .foregroundStyle(state.routeGuidance.running ? .green : .secondary)
                }

                Text(state.routeGuidance.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Selected source", value: state.routeGuidance.selectedSource)
                LabeledContent("Current road", value: state.routeGuidance.currentRoad)
                LabeledContent("Destination", value: state.routeGuidance.destination)
                LabeledContent("Next maneuver", value: state.routeGuidance.distanceToManeuverText)
                LabeledContent("ETA", value: state.routeGuidance.etaText)

                HStack {
                    Button("Start") {
                        state.routeGuidance.start(reason: "Navigation UI")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.routeGuidance.running)

                    Button("Refresh") {
                        state.routeGuidance.refreshNow()
                    }
                    .buttonStyle(.bordered)

                    Button("Stop") {
                        state.routeGuidance.stop(reason: "Navigation UI")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!state.routeGuidance.running)
                }

                Text("Source priority: Google Maps > Apple Maps > Waze. A higher-priority source wins only while its Route Guidance stream is fresh; OCR automatically remains the fallback if the adapter feed disappears. Navigation dashboard default: Speed on the left, ETA on the right.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !state.routeGuidance.lastError.isEmpty {
                    Text("Last adapter error: \(state.routeGuidance.lastError)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
