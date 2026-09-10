import SwiftUI

/// v90.34.17 in-app design/calibration preview for the proposed CarPlay map-video HUD.
///
/// This component is intentionally presentation-only. It reads existing live app
/// state when available, but does not enqueue HUD packets, change navigation
/// ownership, or write any settings used by the physical HUD. The controls below
/// modify only this preview so the layout can be evaluated before a transport path
/// for map video is connected to the HUD.
struct NavigationHUDPreviewCard: View {
    @Bindable var state: AppState

    @State private var layout: PreviewLayout = .leftCenterRight
    @State private var mapScale = 1.08
    @State private var mapCropX = 0.0
    @State private var softEdgeFade = true
    @State private var blockNudgeX = 0.0
    @State private var blockNudgeY = 0.0

    private let previewBlue = Color(red: 0.20, green: 0.64, blue: 1.00)

    var body: some View {
        HudCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .foregroundStyle(previewBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Map Video Display (Preview)")
                            .font(.headline)
                        Text("CarPlay map-video layout concept — in-app preview only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                hudPreview
                    .aspectRatio(2.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }

                VStack(spacing: 10) {
                    HStack {
                        Text("Layout")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }

                    Picker("Layout", selection: $layout) {
                        ForEach(PreviewLayout.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(previewBlue)

                    controlSlider(
                        icon: "map",
                        title: "Map Size",
                        value: $mapScale,
                        range: 0.90...1.45,
                        step: 0.01
                    )

                    controlSlider(
                        icon: "crop",
                        title: "Map Crop Position",
                        value: $mapCropX,
                        range: -1.0...1.0,
                        step: 0.02
                    )

                    Toggle(isOn: $softEdgeFade) {
                        Label("Soft Edge Fade", systemImage: "circle.dotted")
                    }
                    .tint(previewBlue)

                    HStack(spacing: 10) {
                        Label("Move Blocks", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        nudgeButton("arrow.left") { blockNudgeX -= 4 }
                        nudgeButton("arrow.up") { blockNudgeY -= 4 }
                        nudgeButton("arrow.down") { blockNudgeY += 4 }
                        nudgeButton("arrow.right") { blockNudgeX += 4 }
                    }

                    HStack {
                        Image(systemName: "info.circle")
                        Text("Preview controls are local to this screen. Physical-HUD output is unchanged in v90.34.17.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hudPreview: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let widths = layout.widthFractions

            ZStack {
                Color.black

                HStack(spacing: 0) {
                    speedBlock
                        .frame(width: size.width * widths.left)
                        .offset(x: blockNudgeX, y: blockNudgeY)

                    mapBlock
                        .frame(width: size.width * widths.center)

                    navigationBlock
                        .frame(width: size.width * widths.right)
                        .offset(x: blockNudgeX, y: blockNudgeY)
                }

                if layout == .minimal {
                    VStack {
                        Spacer()
                        HStack(spacing: 7) {
                            Image(systemName: previewManeuver.symbol)
                                .font(.caption.bold())
                            Text(previewDistance)
                                .font(.caption.bold())
                            Text(previewStreet)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(previewETA)
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.82))
                    }
                }
            }
        }
    }

    private var speedBlock: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 2)

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.13), lineWidth: 2)
                Circle()
                    .trim(from: 0.08, to: 0.70)
                    .stroke(
                        previewBlue,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(86))

                VStack(spacing: -2) {
                    Text("\(previewSpeed)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                    Text("mph")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 72, maxHeight: 72)

            Text("SPEED LIMIT")
                .font(.system(size: 6, weight: .bold))
                .foregroundStyle(.secondary)
            Text("\(previewLimit)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(.white, lineWidth: 1.4)
                }

            Spacer(minLength: 2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
    }

    private var mapBlock: some View {
        GeometryReader { proxy in
            Image("CarPlayMapPreview")
                .resizable()
                .scaledToFill()
                .scaleEffect(mapScale)
                .offset(x: mapCropX * proxy.size.width * 0.16)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .mask {
                    if softEdgeFade {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .white, location: 0.09),
                                .init(color: .white, location: 0.91),
                                .init(color: .clear, location: 1.00)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Rectangle().fill(.white)
                    }
                }
        }
    }

    private var navigationBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: previewManeuver.symbol)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(previewBlue)
                Spacer(minLength: 2)
            }

            Text(previewDistance)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.55)
                .lineLimit(1)

            Text(previewStreet)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Divider()
                .overlay(.white.opacity(0.25))

            HStack(spacing: 3) {
                laneArrow(active: false, symbol: "arrow.up")
                laneArrow(active: false, symbol: "arrow.up")
                laneArrow(active: false, symbol: "arrow.up")
                laneArrow(active: true, symbol: "arrow.turn.up.right")
            }

            Spacer(minLength: 0)

            Text(previewETA)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 7)
        .padding(.horizontal, 7)
    }

    private func laneArrow(active: Bool, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(active ? previewBlue : .white.opacity(0.34))
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func controlSlider(
        icon: String,
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(title)
                .font(.subheadline)
                .frame(width: 116, alignment: .leading)
            Slider(value: value, in: range, step: step)
                .tint(previewBlue)
        }
    }

    private func nudgeButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.bold())
                .frame(width: 29, height: 29)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var previewSpeed: Int {
        let live = state.speedEngine.currentSpeedMph
        return live > 0 ? live : 43
    }

    private var previewLimit: Int {
        let live = state.speedEngine.currentSpeedLimitMph
        return live > 0 ? live : 35
    }

    private var hasLiveRoutePreview: Bool {
        state.routeGuidance.selectedSource != "—"
    }

    private var previewManeuver: HudManeuver {
        hasLiveRoutePreview ? state.navigation.current.maneuver : .right
    }

    private var previewDistance: String {
        guard hasLiveRoutePreview else { return "500 ft" }
        let source = state.routeGuidance.distanceToManeuverText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !source.isEmpty, source != "—" { return source }
        let exact = state.navigation.current.displayDistanceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !exact.isEmpty { return exact }
        let meters = state.navigation.current.distanceMeters
        guard meters > 0 else { return "—" }
        let feet = Int((Double(meters) * 3.28084).rounded())
        return feet >= 5280
            ? String(format: "%.1f mi", Double(feet) / 5280.0)
            : "\(feet) ft"
    }

    private var previewStreet: String {
        guard hasLiveRoutePreview else { return "Market St" }
        let street = state.navigation.current.streetName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return street.isEmpty ? "Upcoming road" : street
    }

    private var previewETA: String {
        let eta = state.routeGuidance.etaText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return hasLiveRoutePreview && !eta.isEmpty && eta != "—" ? eta : "5:56"
    }
}

private enum PreviewLayout: String, CaseIterable, Identifiable {
    case leftCenterRight
    case mapFocus
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftCenterRight: return "Left–Center–Right"
        case .mapFocus: return "Map Focus"
        case .minimal: return "Minimal"
        }
    }

    var widthFractions: (left: CGFloat, center: CGFloat, right: CGFloat) {
        switch self {
        case .leftCenterRight:
            return (0.22, 0.53, 0.25)
        case .mapFocus:
            return (0.17, 0.63, 0.20)
        case .minimal:
            return (0.00, 1.00, 0.00)
        }
    }
}
