import SwiftUI
import UIKit

/// Shared 480x240-friendly composition used by both the in-app preview and the
/// experimental KivicCast MJPEG output.
struct HudMapModeCanvas: View {
    let snapshot: HudMapModeSnapshot
    let settings: HudMapModeSettings
    var sourceMapImage: UIImage? = nil
    var previewLanePlaceholder = false
    var suppressCustomSpeedForNativeOBDProbe = false

    private let routeBlue = Color(red: 0.18, green: 0.62, blue: 1.00)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.black

                HStack(spacing: 0) {
                    leftWidget
                        .frame(width: size.width * 0.20, height: size.height)
                        .scaleEffect(settings.leftScale)
                        .offset(
                            x: CGFloat(settings.leftOffsetX),
                            y: CGFloat(settings.leftOffsetY)
                        )

                    centerWidget
                        .frame(width: size.width * 0.58, height: size.height)
                        .scaleEffect(settings.centerScale)
                        .offset(
                            x: CGFloat(settings.centerOffsetX),
                            y: CGFloat(settings.centerOffsetY)
                        )

                    rightWidget
                        .frame(width: size.width * 0.22, height: size.height)
                        .scaleEffect(settings.rightScale)
                        .offset(
                            x: CGFloat(settings.rightOffsetX),
                            y: CGFloat(settings.rightOffsetY)
                        )
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .background(Color.black)
    }

    private var leftWidget: some View {
        VStack(spacing: 7) {
            Spacer(minLength: 10)

            if settings.showSpeed && !suppressCustomSpeedForNativeOBDProbe {
                VStack(spacing: -3) {
                    Text("\(max(0, snapshot.speedMph))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.55)
                        .lineLimit(1)
                    Text("MPH")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.60))
                }
            } else if settings.showSpeed && suppressCustomSpeedForNativeOBDProbe {
                // Deliberately reserve the left speed area during the physical
                // OBD-overlay experiment. Any number visible on the HUD is then
                // unambiguously produced by the stock OBD renderer, not GPS.
                Color.clear.frame(height: 60)
            }

            if settings.showSpeedLimit {
                usSpeedLimitSign
            }

            Spacer(minLength: 10)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    private var usSpeedLimitSign: some View {
        VStack(spacing: -1) {
            Text("SPEED")
                .font(.system(size: 6.5, weight: .bold))
            Text("LIMIT")
                .font(.system(size: 6.5, weight: .bold))
            Text(snapshot.speedLimitMph > 0 ? "\(snapshot.speedLimitMph)" : "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.black)
        .frame(width: 42, height: 50)
        .background(.white)
        .overlay {
            RoundedRectangle(cornerRadius: 2)
                .stroke(.black, lineWidth: 1.5)
                .padding(2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private var centerWidget: some View {
        if settings.showMap {
            Group {
                if let sourceMapImage {
                    HudMapModeSourceCrop(
                        image: sourceMapImage,
                        appearance: settings.mapAppearance,
                        zoom: settings.sourceMapZoom,
                        offsetX: settings.sourceMapOffsetX,
                        offsetY: settings.sourceMapOffsetY
                    )
                } else {
                    HudMapModeSchematic(
                        snapshot: snapshot,
                        appearance: settings.mapAppearance,
                        routeBlue: routeBlue
                    )
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
        } else {
            Color.clear
        }
    }

    private var rightWidget: some View {
        VStack(alignment: .center, spacing: 4) {
            Spacer(minLength: 8)

            if settings.showTurningStreet {
                Text(nonempty(snapshot.turningStreet, fallback: "Upcoming road"))
                    .font(.system(
                        size: CGFloat(11 * settings.turningStreetScale),
                        weight: .semibold
                    ))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if settings.showManeuver {
                Image(systemName: snapshot.maneuver.symbol)
                    .font(.system(
                        size: CGFloat(34 * settings.maneuverArrowScale),
                        weight: symbolWeight(settings.maneuverArrowThickness)
                    ))
                    .foregroundStyle(.white)
                    .frame(height: 40)
                    .offset(
                        x: CGFloat(settings.maneuverOffsetX),
                        y: CGFloat(settings.maneuverOffsetY)
                    )
            }

            if settings.showDistance {
                Text(nonempty(snapshot.distanceText, fallback: "—"))
                    .font(.system(
                        size: CGFloat(19 * settings.distanceScale),
                        weight: .bold,
                        design: .rounded
                    ))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
            }

            if settings.showLaneGuidance {
                laneGuidanceRow
                    .frame(height: 25)
                    .scaleEffect(settings.laneScale)
                    .offset(
                        x: CGFloat(settings.laneOffsetX),
                        y: CGFloat(settings.laneOffsetY)
                    )
            }

            if settings.showETA || settings.showTimeLeft {
                VStack(spacing: 0) {
                    if settings.showETA {
                        Text("ETA \(nonempty(snapshot.etaText, fallback: "—"))")
                            .font(.system(
                                size: CGFloat(9.5 * settings.etaScale),
                                weight: .semibold,
                                design: .rounded
                            ))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    if settings.showTimeLeft {
                        Text(nonempty(snapshot.timeLeftText, fallback: "—"))
                            .font(.system(
                                size: CGFloat(9.5 * settings.etaScale),
                                weight: .medium,
                                design: .rounded
                            ))
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)
                    }
                }
                .offset(
                    x: CGFloat(settings.etaOffsetX),
                    y: CGFloat(settings.etaOffsetY)
                )
            }

            Spacer(minLength: 8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var effectiveLaneValues: [Int] {
        if !snapshot.laneValues.isEmpty { return snapshot.laneValues }
        return previewLanePlaceholder ? [-1, -1, 2] : []
    }

    @ViewBuilder
    private var laneGuidanceRow: some View {
        let values = effectiveLaneValues
        if values.isEmpty {
            Color.clear
        } else {
            HStack(spacing: CGFloat(settings.laneSpacing)) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Image(systemName: laneSymbol(for: abs(value)))
                        .font(.system(
                            size: 11,
                            weight: symbolWeight(settings.laneArrowThickness)
                        ))
                        .foregroundStyle(value > 0 ? .white : .white.opacity(0.22))
                        .scaleEffect(value > 0 ? settings.laneActiveEmphasis : 1.0)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func symbolWeight(_ thickness: Double) -> Font.Weight {
        switch thickness {
        case ..<1.25: return .regular
        case ..<1.50: return .medium
        case ..<1.75: return .semibold
        case ..<2.00: return .bold
        case ..<2.25: return .heavy
        default: return .black
        }
    }

    private func laneSymbol(for raw: Int) -> String {
        switch raw {
        case 2: return "arrow.turn.up.right"
        case 3: return "arrow.up.right"
        case 4: return "arrow.turn.up.left"
        case 5: return "arrow.up.left"
        default: return "arrow.up"
        }
    }

    private func nonempty(_ value: String, fallback: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "—" ? fallback : cleaned
    }
}


private struct HudMapModeSourceCrop: View {
    let image: UIImage
    let appearance: HudMapAppearance
    let zoom: Double
    let offsetX: Double
    let offsetY: Double

    var body: some View {
        GeometryReader { proxy in
            sourceImage
                .scaleEffect(zoom)
                .offset(
                    x: offsetX * proxy.size.width,
                    y: offsetY * proxy.size.height
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .white, location: 0.045),
                            .init(color: .white, location: 0.955),
                            .init(color: .clear, location: 1.00)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var sourceImage: some View {
        let base = Image(uiImage: image)
            .resizable()
            .scaledToFill()

        switch appearance {
        case .followSource:
            base
        case .darkHUD:
            base
                .saturation(0.82)
                .brightness(-0.30)
                .contrast(1.18)
        case .lightHUD:
            base
                .saturation(0.90)
                .brightness(0.08)
                .contrast(1.05)
        }
    }
}

private struct HudMapModeSchematic: View {
    let snapshot: HudMapModeSnapshot
    let appearance: HudMapAppearance
    let routeBlue: Color

    private var isLight: Bool { appearance == .lightHUD }
    private var ground: Color { isLight ? Color(white: 0.82) : Color(red: 0.015, green: 0.025, blue: 0.035) }
    private var road: Color { isLight ? Color(white: 0.38) : Color.white.opacity(0.18) }
    private var label: Color { isLight ? .black.opacity(0.72) : .white.opacity(0.67) }
    private var block: Color { isLight ? Color(white: 0.70) : Color.white.opacity(0.045) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ground)

                Canvas { context, canvasSize in
                    drawRoadGrid(context: &context, size: canvasSize)
                    drawBlocks(context: &context, size: canvasSize)
                    drawRoute(context: &context, size: canvasSize)
                }

                routeLabels(size: size)

                Image(systemName: "location.north.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: routeBlue.opacity(0.75), radius: 5)
                    .position(x: size.width * 0.48, y: size.height * 0.76)

                if !snapshot.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   snapshot.destination != "—" {
                    VStack(spacing: 0) {
                        Text(snapshot.destination)
                            .font(.system(size: 6.5, weight: .semibold))
                            .foregroundStyle(isLight ? .black : .white)
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(routeBlue)
                    }
                    .position(x: destinationX(size.width), y: size.height * 0.26)
                }

                VStack(spacing: -1) {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("N").font(.system(size: 5, weight: .medium))
                }
                .foregroundStyle(label)
                .position(x: size.width * 0.91, y: size.height * 0.13)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .white, location: 0.05),
                        .init(color: .white, location: 0.95),
                        .init(color: .clear, location: 1.00)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }

    private func drawRoadGrid(context: inout GraphicsContext, size: CGSize) {
        let verticals: [CGFloat] = [0.22, 0.48, 0.72]
        let horizontals: [CGFloat] = [0.24, 0.44, 0.64, 0.82]

        for x in verticals {
            var path = Path()
            path.move(to: CGPoint(x: size.width * x, y: size.height * 0.06))
            path.addLine(to: CGPoint(x: size.width * (x + (x - 0.48) * 0.34), y: size.height * 0.95))
            context.stroke(path, with: .color(road), lineWidth: 2)
        }
        for y in horizontals {
            var path = Path()
            path.move(to: CGPoint(x: size.width * 0.03, y: size.height * y))
            path.addLine(to: CGPoint(x: size.width * 0.97, y: size.height * (y + (y - 0.50) * 0.04)))
            context.stroke(path, with: .color(road), lineWidth: 2)
        }
    }

    private func drawBlocks(context: inout GraphicsContext, size: CGSize) {
        let rects: [CGRect] = [
            CGRect(x: 0.07, y: 0.29, width: 0.13, height: 0.10),
            CGRect(x: 0.28, y: 0.16, width: 0.13, height: 0.10),
            CGRect(x: 0.56, y: 0.31, width: 0.11, height: 0.11),
            CGRect(x: 0.76, y: 0.51, width: 0.15, height: 0.12),
            CGRect(x: 0.09, y: 0.69, width: 0.17, height: 0.12),
            CGRect(x: 0.58, y: 0.70, width: 0.14, height: 0.12),
        ]
        for unit in rects {
            let rect = CGRect(
                x: unit.minX * size.width,
                y: unit.minY * size.height,
                width: unit.width * size.width,
                height: unit.height * size.height
            )
            var path = Path()
            path.addRect(rect)
            context.fill(path, with: .color(block))
        }
    }

    private func drawRoute(context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        path.move(to: CGPoint(x: size.width * 0.48, y: size.height * 0.94))
        path.addCurve(
            to: CGPoint(x: size.width * 0.49, y: size.height * 0.34),
            control1: CGPoint(x: size.width * 0.47, y: size.height * 0.72),
            control2: CGPoint(x: size.width * 0.50, y: size.height * 0.46)
        )

        switch snapshot.maneuver {
        case .left, .slightLeft, .sharpLeft, .keepLeft, .exitLeft, .uTurn:
            path.addCurve(
                to: CGPoint(x: size.width * 0.20, y: size.height * 0.25),
                control1: CGPoint(x: size.width * 0.42, y: size.height * 0.25),
                control2: CGPoint(x: size.width * 0.28, y: size.height * 0.25)
            )
        case .right, .slightRight, .sharpRight, .keepRight, .exitRight, .roundabout:
            path.addCurve(
                to: CGPoint(x: size.width * 0.80, y: size.height * 0.25),
                control1: CGPoint(x: size.width * 0.56, y: size.height * 0.25),
                control2: CGPoint(x: size.width * 0.70, y: size.height * 0.25)
            )
        default:
            path.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.08))
        }

        context.stroke(path, with: .color(routeBlue.opacity(0.28)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(routeBlue), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder
    private func routeLabels(size: CGSize) -> some View {
        let labels = cleanedRoadLabels
        if !labels.isEmpty {
            ForEach(Array(labels.prefix(6).enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.system(size: 5.4, weight: .medium))
                    .foregroundStyle(label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .position(labelPosition(index: index, size: size))
            }
        }

        if !snapshot.currentRoad.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           snapshot.currentRoad != "—" {
            Text(snapshot.currentRoad)
                .font(.system(size: 6.2, weight: .semibold))
                .foregroundStyle(label)
                .position(x: size.width * 0.49, y: size.height * 0.88)
        }
    }

    private var cleanedRoadLabels: [String] {
        var seen = Set<String>()
        var output: [String] = []
        let candidates = snapshot.routeRoads + [snapshot.turningStreet]
        for raw in candidates {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value != "—", !seen.contains(value), value != snapshot.currentRoad else { continue }
            seen.insert(value)
            output.append(value)
        }
        return output
    }

    private func labelPosition(index: Int, size: CGSize) -> CGPoint {
        let positions: [(CGFloat, CGFloat)] = [
            (0.28, 0.20), (0.70, 0.43), (0.26, 0.48),
            (0.73, 0.68), (0.27, 0.76), (0.72, 0.23)
        ]
        let p = positions[index % positions.count]
        return CGPoint(x: size.width * p.0, y: size.height * p.1)
    }

    private func destinationX(_ width: CGFloat) -> CGFloat {
        switch snapshot.maneuver {
        case .left, .slightLeft, .sharpLeft, .keepLeft, .exitLeft, .uTurn:
            return width * 0.24
        case .right, .slightRight, .sharpRight, .keepRight, .exitRight, .roundabout:
            return width * 0.76
        default:
            return width * 0.51
        }
    }
}
