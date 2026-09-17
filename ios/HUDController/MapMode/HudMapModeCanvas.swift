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
                            x: CGFloat(settings.centerOffsetX + settings.designerMapOffsetX),
                            y: CGFloat(settings.centerOffsetY + settings.designerMapOffsetY)
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

            Group {
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
                    .scaleEffect(settings.speedScale)
                    .offset(
                        x: CGFloat(settings.designerSpeedOffsetX / max(0.01, settings.leftScale)),
                        y: CGFloat(settings.designerSpeedOffsetY / max(0.01, settings.leftScale))
                    )
                } else {
                    // Keep a fixed speed slot even when the native item-10 probe owns
                    // this region. That prevents any vertical layout shift.
                    Color.clear.frame(height: 60)
                }
            }
            .frame(height: 60)

            Group {
                if settings.showSpeedLimit && snapshot.speedLimitMph > 0 {
                    usSpeedLimitSign
                } else {
                    // No OSM speed limit = no white rectangle. Preserve the exact
                    // sign slot so the speed number never re-centers vertically.
                    Color.clear
                        .frame(width: 42, height: CGFloat(34 * settings.speedLimitSignHeightScale))
                }
            }

            Spacer(minLength: 10)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }

    private var usSpeedLimitSign: some View {
        Text("\(snapshot.speedLimitMph)")
            .font(.system(
                size: CGFloat(24 * settings.speedLimitFontScale),
                weight: .bold,
                design: .rounded
            ))
            .minimumScaleFactor(0.55)
            .foregroundStyle(.black)
            .frame(
                width: 42,
                height: CGFloat(34 * settings.speedLimitSignHeightScale)
            )
            .background(.white)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(.black, lineWidth: 1.5)
                    .padding(2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .offset(
                x: CGFloat(settings.designerSpeedLimitOffsetX / max(0.01, settings.leftScale)),
                y: CGFloat(settings.designerSpeedLimitOffsetY / max(0.01, settings.leftScale))
            )
    }

    @ViewBuilder
    private var centerWidget: some View {
        if settings.showMap {
            Group {
                if let sourceMapImage {
                    // Deliberately content-blind: crop the same configured rectangle
                    // from every live CarPlay frame. Dashboard, Maps, Music, or any
                    // other CarPlay screen is treated identically.
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
            .mask(edgeFadeMask(
                fraction: settings.mapFadeHorizontal,
                startPoint: .leading,
                endPoint: .trailing
            ))
            .mask(edgeFadeMask(
                fraction: settings.mapFadeVertical,
                startPoint: .top,
                endPoint: .bottom
            ))
        } else {
            Color.clear
        }
    }

    private var rightWidget: some View {
        VStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 8)

            if settings.showTurningStreet {
                Text(nonempty(snapshot.turningStreet, fallback: "Upcoming road"))
                    .font(.system(
                        size: CGFloat(11 * settings.turningStreetScale),
                        weight: .semibold
                    ))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.50)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .offset(
                        x: CGFloat(settings.designerStreetOffsetX / max(0.01, settings.rightScale)),
                        y: CGFloat(settings.designerStreetOffsetY / max(0.01, settings.rightScale))
                    )
            }

            if settings.showTurningStreet && (settings.showManeuver || settings.showDistance) {
                Color.clear.frame(height: CGFloat(settings.streetToManeuverSpacing))
            }

            if settings.showManeuver || settings.showDistance {
                VStack(spacing: 2) {
                    if settings.showManeuver {
                        Image(systemName: snapshot.maneuver.symbol)
                            .font(.system(
                                size: CGFloat(34 * settings.maneuverArrowScale),
                                weight: symbolWeight(settings.maneuverArrowThickness)
                            ))
                            .foregroundStyle(.white)
                            .frame(height: CGFloat(40 * max(1.0, settings.maneuverArrowScale)))
                            .offset(
                                x: CGFloat(settings.maneuverOffsetX + settings.designerManeuverOffsetX / max(0.01, settings.rightScale)),
                                y: CGFloat(settings.maneuverOffsetY + settings.designerManeuverOffsetY / max(0.01, settings.rightScale))
                            )
                    }

                    if settings.showDistance {
                        Text(nonempty(snapshot.distanceText, fallback: "—"))
                            .font(.system(
                                size: CGFloat(19 * settings.distanceScale),
                                weight: .bold,
                                design: .rounded
                            ))
                            .minimumScaleFactor(0.50)
                            .lineLimit(1)
                            .offset(
                                x: CGFloat(settings.designerDistanceOffsetX / max(0.01, settings.rightScale)),
                                y: CGFloat(settings.designerDistanceOffsetY / max(0.01, settings.rightScale))
                            )
                    }
                }
            }

            if (settings.showManeuver || settings.showDistance) && settings.showLaneGuidance {
                Color.clear.frame(height: CGFloat(settings.maneuverToLaneSpacing))
            }

            if settings.showLaneGuidance {
                laneGuidanceRow
                    .frame(height: CGFloat(25 * max(1.0, settings.laneScale)))
                    .scaleEffect(settings.laneScale)
                    .offset(
                        x: CGFloat(settings.laneOffsetX + settings.designerLaneOffsetX / max(0.01, settings.rightScale)),
                        y: CGFloat(settings.laneOffsetY + settings.designerLaneOffsetY / max(0.01, settings.rightScale))
                    )
            }

            if settings.showLaneGuidance && (settings.showETA || settings.showTimeLeft) {
                Color.clear.frame(height: CGFloat(settings.laneToETASpacing))
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
                            .minimumScaleFactor(0.55)
                            .offset(
                                x: CGFloat(settings.designerETAOffsetX / max(0.01, settings.rightScale)),
                                y: CGFloat(settings.designerETAOffsetY / max(0.01, settings.rightScale))
                            )
                    }
                    if settings.showTimeLeft {
                        Text(nonempty(snapshot.timeLeftText, fallback: "—"))
                            .font(.system(
                                size: CGFloat(9.5 * settings.etaScale * settings.timeLeftScale),
                                weight: .medium,
                                design: .rounded
                            ))
                            .foregroundStyle(.white.opacity(0.64))
                            .lineLimit(1)
                            .offset(
                                x: CGFloat(settings.designerTimeLeftOffsetX / max(0.01, settings.rightScale)),
                                y: CGFloat(settings.designerTimeLeftOffsetY / max(0.01, settings.rightScale))
                            )
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

    /// The physical right-side lane area is intentionally optimized for four
    /// readable arrows. For 1...4 lanes, every arrow is packed contiguously and
    /// the whole group is centered. For 5+ lanes, select the best four-lane
    /// window around the recommended (positive) lane cluster rather than shrinking
    /// every glyph until it becomes unreadable.
    private var displayedLaneValues: [Int] {
        let values = effectiveLaneValues
        guard values.count > 4 else { return values }

        let active = values.indices.filter { values[$0] > 0 }
        guard !active.isEmpty else {
            let start = max(0, (values.count - 4) / 2)
            return Array(values[start..<(start + 4)])
        }

        let activeCenter = Double(active.reduce(0, +)) / Double(active.count)
        var bestStart = 0
        var bestScore = -Double.infinity
        for start in 0...(values.count - 4) {
            let range = start..<(start + 4)
            let activeInside = active.filter { range.contains($0) }.count
            let windowCenter = Double(start) + 1.5
            // First maximize how many recommended lanes are retained; then prefer
            // the window whose center is nearest the recommended-lane centroid.
            let score = Double(activeInside) * 100.0 - abs(windowCenter - activeCenter)
            if score > bestScore {
                bestScore = score
                bestStart = start
            }
        }
        return Array(values[bestStart..<(bestStart + 4)])
    }

    @ViewBuilder
    private var laneGuidanceRow: some View {
        let values = displayedLaneValues
        if values.isEmpty {
            Color.clear
        } else {
            HStack(spacing: CGFloat(settings.laneSpacing)) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    laneGlyph(for: abs(value))
                        .font(.system(
                            size: 11,
                            weight: symbolWeight(settings.laneArrowThickness)
                        ))
                        .foregroundStyle(value > 0 ? .white : Color(white: settings.laneInactiveGray))
                        .scaleEffect(value > 0 ? settings.laneActiveEmphasis : 1.0)
                        .frame(width: 14, height: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func edgeFadeMask(
        fraction: Double,
        startPoint: UnitPoint,
        endPoint: UnitPoint
    ) -> some View {
        let f = min(0.35, max(0.0, fraction))
        if f <= 0.001 {
            Color.white
        } else {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .white, location: f),
                    .init(color: .white, location: 1.0 - f),
                    .init(color: .clear, location: 1.00)
                ],
                startPoint: startPoint,
                endPoint: endPoint
            )
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

    @ViewBuilder
    private func laneGlyph(for raw: Int) -> some View {
        switch raw {
        case 2:
            Image(systemName: "arrow.turn.up.right")
        case 3:
            // Native lane type 3 means straight OR right. Overlay the straight
            // and turn glyphs instead of collapsing it to a diagonal arrow.
            ZStack {
                Image(systemName: "arrow.up")
                Image(systemName: "arrow.turn.up.right")
            }
        case 4:
            Image(systemName: "arrow.turn.up.left")
        case 5:
            // Native lane type 5 means straight OR left.
            ZStack {
                Image(systemName: "arrow.up")
                Image(systemName: "arrow.turn.up.left")
            }
        default:
            Image(systemName: "arrow.up")
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
