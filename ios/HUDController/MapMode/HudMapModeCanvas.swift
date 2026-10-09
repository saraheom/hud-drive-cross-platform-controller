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
    /// When non-nil, keep the component's layout slot but render it transparent.
    /// This is the close-maneuver warning blink used by Map Mode only.
    var warningHiddenTarget: HudManeuverWarningTarget? = nil

    private let routeBlue = Color(red: 0.18, green: 0.62, blue: 1.00)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(
                proxy.size.width / 480.0,
                proxy.size.height / 240.0
            )
            ZStack {
                Color.black
                canonicalCanvas
                    .frame(width: 480, height: 240)
                    .scaleEffect(scale, anchor: .center)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color.black)
    }

    /// v90.35.3.24.29 renders every Map Mode element directly on one canonical
    /// 480x240 coordinate space. The old 20% / 58% / 22% parent HStack is gone;
    /// the same final coordinates are therefore used by the phone preview and by
    /// the 480x240 JPEG sent to the physical HUD.
    private var canonicalCanvas: some View {
        ZStack {
            Color.black

            if settings.showMap && snapshot.hasLiveRoute {
                mapBlock
                    .frame(width: 278, height: 240)
                    .scaleEffect(settings.centerScale)
                    .position(canvasPoint(.map))
            }

            if settings.showSpeed && !suppressCustomSpeedForNativeOBDProbe {
                speedBlock
                    .frame(width: 96, height: 72)
                    .scaleEffect(settings.speedScale * settings.leftScale)
                    .position(canvasPoint(.speed))
            }

            if settings.showSpeedLimit && snapshot.speedLimitMph > 0 {
                usSpeedLimitSign
                    .scaleEffect(settings.leftScale)
                    .position(canvasPoint(.speedLimit))
            }

            if snapshot.hasLiveRoute {
                if settings.showTurningStreet {
                    streetBlock
                        .frame(width: 108, height: 34)
                        .scaleEffect(settings.rightScale)
                        .position(canvasPoint(.turningStreet))
                }

                if settings.showManeuver {
                    maneuverBlock
                        .frame(width: 80, height: 58)
                        .scaleEffect(settings.rightScale)
                        .position(canvasPoint(.maneuver))
                }

                if settings.showDistance {
                    distanceBlock
                        .frame(width: 108, height: 34)
                        .scaleEffect(settings.rightScale)
                        .position(canvasPoint(.distance))
                }

                if laneGuidanceAvailable {
                    laneGuidanceRow
                        .frame(width: 112, height: CGFloat(30 * max(1.0, settings.laneScale)))
                        .scaleEffect(settings.laneScale * settings.rightScale)
                        .position(canvasPoint(.lanes))
                }

                // ETA/lane sharing is intentionally mutually exclusive in this shared
                // renderer. The phone designer preview and the physical 480x240 JPEG both
                // execute this exact path: real/sample lane arrows win; ETA occupies the
                // same Lane Guidance coordinate only while lane guidance is unavailable.
                if shouldRenderETA {
                    etaBlock
                        .scaleEffect(settings.rightScale)
                        .position(canvasPoint(etaCanvasComponent))
                }

                if settings.showTimeLeft {
                    timeLeftBlock
                        .scaleEffect(settings.rightScale)
                        .position(canvasPoint(.timeLeft))
                }
            }
        }
        .frame(width: 480, height: 240)
        .foregroundStyle(.white)
        .clipped()
    }

    private func canvasPoint(_ component: HudMapDesignerComponent) -> CGPoint {
        let p = settings.designerCanvasPosition(for: component)
        return CGPoint(x: p.x, y: p.y)
    }

    private var speedBlock: some View {
        VStack(spacing: -3) {
            Text("\(max(0, snapshot.speedMph))")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.55)
                .lineLimit(1)
                .foregroundStyle(speedNumberColor)
                .padding(.horizontal, speedWarningActive && settings.speedWarningBackgroundEnabled ? 6 : 0)
                .padding(.vertical, speedWarningActive && settings.speedWarningBackgroundEnabled ? 1 : 0)
                .background {
                    if speedWarningActive && settings.speedWarningBackgroundEnabled {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(speedWarningBackgroundColor.opacity(settings.speedWarningBackgroundOpacity))
                    }
                }
            Text("MPH")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.60))
        }
    }

    private var speedWarningActive: Bool {
        settings.speedWarningEnabled &&
        snapshot.speedLimitMph > 0 &&
        snapshot.speedMph > snapshot.speedLimitMph
    }

    private var speedNumberColor: Color {
        guard speedWarningActive && settings.speedWarningNumberColorEnabled else { return .white }
        return Color(
            red: settings.speedWarningNumberRed,
            green: settings.speedWarningNumberGreen,
            blue: settings.speedWarningNumberBlue
        )
    }

    private var speedWarningBackgroundColor: Color {
        Color(
            red: settings.speedWarningBackgroundRed,
            green: settings.speedWarningBackgroundGreen,
            blue: settings.speedWarningBackgroundBlue
        )
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
    }

    @ViewBuilder
    private var mapBlock: some View {
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
    }

    private var streetBlock: some View {
        Text(nonempty(snapshot.turningStreet, fallback: "Upcoming road"))
            .font(.system(
                size: CGFloat(10.5 * settings.turningStreetScale),
                weight: .semibold
            ))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.62)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .frame(width: 104, height: 32, alignment: .center)
    }

    @ViewBuilder
    private var maneuverBlock: some View {
        Group {
            if let mergeKind = mergeManeuverKind {
                MergeManeuverGlyph(
                    kind: mergeKind,
                    color: .white,
                    lineWidth: CGFloat(max(1.0, min(3.0, settings.maneuverArrowThickness * 1.05)))
                )
                .frame(width: 34, height: 38)
            } else {
                Image(systemName: snapshot.maneuver.symbol)
                    .font(.system(size: 34, weight: symbolWeight(settings.maneuverArrowThickness)))
            }
        }
        .foregroundStyle(.white)
        .opacity(warningHiddenTarget == .maneuverArrow ? 0 : 1)
        .scaleEffect(settings.maneuverArrowScale)
    }

    private var distanceBlock: some View {
        Text(nonempty(snapshot.distanceText, fallback: "—"))
            .font(.system(
                size: CGFloat(19 * settings.distanceScale),
                weight: .bold,
                design: .rounded
            ))
            .minimumScaleFactor(0.50)
            .lineLimit(1)
            .opacity(warningHiddenTarget == .distance ? 0 : 1)
    }

    private var laneGuidanceAvailable: Bool {
        settings.showLaneGuidance && !effectiveLaneValues.isEmpty
    }

    /// Shared ETA/lane policy used identically by the in-app designer preview and
    /// the physical HUD renderer. When sharing is enabled, ETA and lane guidance
    /// can never be visible at the same time.
    private var shouldRenderETA: Bool {
        guard settings.showETA else { return false }
        guard settings.etaUsesLanePositionWhenNoLanes else { return true }
        return !laneGuidanceAvailable
    }

    private var etaCanvasComponent: HudMapDesignerComponent {
        settings.etaUsesLanePositionWhenNoLanes ? .lanes : .eta
    }

    private var etaBlock: some View {
        Text("ETA \(etaDisplayText(snapshot.etaText))")
            .font(.system(
                size: CGFloat(9.5 * settings.etaScale),
                weight: .semibold,
                design: .rounded
            ))
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(width: 118, height: 24)
    }

    private var timeLeftBlock: some View {
        Text(nonempty(snapshot.timeLeftText, fallback: "—"))
            .font(.system(
                size: CGFloat(9.5 * settings.etaScale * settings.timeLeftScale),
                weight: .medium,
                design: .rounded
            ))
            .foregroundStyle(.white.opacity(0.64))
            .lineLimit(1)
            .frame(width: 118, height: 22)
    }

    private func etaDisplayText(_ raw: String) -> String {
        let value = nonempty(raw, fallback: "—")
        guard !settings.showETAAMPM else { return value }
        let parts = value.split(separator: " ", omittingEmptySubsequences: true)
        guard let suffix = parts.last?.uppercased(), suffix == "AM" || suffix == "PM" else {
            return value
        }
        let shortened = parts.dropLast().joined(separator: " ")
        return shortened.isEmpty ? value : shortened
    }

    private var mergeManeuverKind: MergeManeuverGlyph.Kind? {
        let text = snapshot.maneuverText.lowercased()
        guard text.contains("merge") || text.contains("merging") else { return nil }
        if text.contains("left") { return .left }
        if text.contains("right") { return .right }
        return .ahead
    }

    private var effectiveLaneValues: [Int] {
        if !snapshot.laneValues.isEmpty { return snapshot.laneValues }
        return previewLanePlaceholder ? [-1, -1, 3] : []
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

    private enum LaneTurnHighlightDirection {
        case none, left, right

        init(maneuver: HudManeuver) {
            switch maneuver {
            case .left, .slightLeft, .sharpLeft, .keepLeft, .exitLeft, .uTurn:
                self = .left
            case .right, .slightRight, .sharpRight, .keepRight, .exitRight, .roundabout:
                self = .right
            default:
                self = .none
            }
        }
    }

    private var laneTurnHighlightDirection: LaneTurnHighlightDirection {
        LaneTurnHighlightDirection(maneuver: snapshot.maneuver)
    }

    private func laneGlyphStyle(for wireValue: Int) -> LaneGuidanceGlyph.Style {
        let recommended = wireValue > 0
        let type = abs(wireValue)
        guard recommended else { return .inactive }

        switch laneTurnHighlightDirection {
        case .left:
            switch type {
            case 4: return .active
            case 5: return .turnOnlyLeft
            case 1: return .inactive
            default: return .active
            }
        case .right:
            switch type {
            case 2: return .active
            case 3: return .turnOnlyRight
            case 1: return .inactive
            default: return .active
            }
        case .none:
            return .active
        }
    }

    @ViewBuilder
    private var laneGuidanceRow: some View {
        let values = displayedLaneValues
        if values.isEmpty {
            Color.clear
        } else {
            let inactiveColor = Color(white: settings.laneInactiveGray)
            HStack(spacing: CGFloat(settings.laneSpacing)) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    let style = laneGlyphStyle(for: value)
                    LaneGuidanceGlyph(
                        rawValue: abs(value),
                        style: style,
                        activeColor: .white,
                        inactiveColor: inactiveColor,
                        lineWidth: CGFloat(max(0.45, min(2.25, settings.laneArrowThickness * 0.82))),
                        headScale: CGFloat(settings.laneArrowHeadScale),
                        bodyLength: CGFloat(settings.laneArrowBodyLength)
                    )
                    .scaleEffect(style.isHighlighted ? settings.laneActiveEmphasis : 1.0)
                    .frame(width: 15, height: 22)
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

    private func nonempty(_ value: String, fallback: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned == "—" ? fallback : cleaned
    }
}


/// Compact lane-guidance vector designed for the 480×240 physical HUD.
/// v90.35.3.20 uses the approved shorter Google-style lane arrows. This changes
/// only lane guidance; the large turn-by-turn maneuver arrow above stays unchanged.
/// Combined straight+turn glyphs share one body, with turn-only white overlays
/// drawn directly on top of the gray straight stem.
private struct LaneGuidanceGlyph: View {
    enum Style {
        case inactive
        case active
        case turnOnlyLeft
        case turnOnlyRight

        var isHighlighted: Bool {
            switch self {
            case .inactive: return false
            default: return true
            }
        }
    }

    let rawValue: Int
    let style: Style
    let activeColor: Color
    let inactiveColor: Color
    let lineWidth: CGFloat
    let headScale: CGFloat
    let bodyLength: CGFloat

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w * 0.5
            // v90.35.3.22 decouples shaft length from arrow-head size. The
            // physical 480×240 HUD made the old long, thin glyph read like a
            // line; a shorter body plus a wider filled head stays identifiable.
            let body = min(1.0, max(0.55, bodyLength))
            let head = min(1.8, max(0.8, headScale))
            let bottom = h * (0.30 + 0.52 * body)
            let straightBaseY = h * 0.30
            let straightApexY = h * 0.12
            let headHalfW = max(1.7, w * 0.17) * head
            let styleStroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            func stroke(_ path: Path, color: Color, opacity: Double = 1.0) {
                context.stroke(path, with: .color(color.opacity(opacity)), style: styleStroke)
            }
            func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, color: Color, opacity: Double = 1.0) {
                var p = Path()
                p.move(to: a)
                p.addLine(to: b)
                p.addLine(to: c)
                p.closeSubpath()
                context.fill(p, with: .color(color.opacity(opacity)))
            }
            func straightArrow(_ drawColor: Color, opacity: Double = 1.0) {
                var shaft = Path()
                shaft.move(to: CGPoint(x: cx, y: bottom))
                shaft.addLine(to: CGPoint(x: cx, y: straightBaseY))
                stroke(shaft, color: drawColor, opacity: opacity)
                triangle(
                    CGPoint(x: cx, y: straightApexY),
                    CGPoint(x: cx - headHalfW, y: straightBaseY),
                    CGPoint(x: cx + headHalfW, y: straightBaseY),
                    color: drawColor,
                    opacity: opacity
                )
            }
            func soloTurn(right: Bool, drawColor: Color, opacity: Double = 1.0) {
                let sign: CGFloat = right ? 1 : -1
                let branchY = min(h * 0.58, max(h * 0.47, bottom - h * 0.10))
                let headY = h * 0.31
                let headX = cx + sign * w * 0.39
                let baseX = headX - sign * w * (0.19 * head)
                let halfH = h * 0.090 * head

                var p = Path()
                p.move(to: CGPoint(x: cx, y: bottom))
                p.addLine(to: CGPoint(x: cx, y: branchY))
                p.addCurve(
                    to: CGPoint(x: baseX, y: headY),
                    control1: CGPoint(x: cx + sign * w * 0.01, y: branchY - h * 0.18),
                    control2: CGPoint(x: baseX - sign * w * 0.16, y: headY + h * 0.02)
                )
                stroke(p, color: drawColor, opacity: opacity)
                triangle(
                    CGPoint(x: headX, y: headY),
                    CGPoint(x: baseX, y: headY - halfH),
                    CGPoint(x: baseX, y: headY + halfH),
                    color: drawColor,
                    opacity: opacity
                )
            }
            func combined(right: Bool, drawColor: Color, opacity: Double = 1.0) {
                straightArrow(drawColor, opacity: opacity)
                let sign: CGFloat = right ? 1 : -1
                let branchStartY = min(h * 0.57, max(h * 0.46, bottom - h * 0.10))
                let headY = h * 0.34
                let headX = cx + sign * w * 0.38
                let baseX = headX - sign * w * (0.18 * head)
                let halfH = h * 0.082 * head
                var branch = Path()
                branch.move(to: CGPoint(x: cx, y: branchStartY))
                branch.addCurve(
                    to: CGPoint(x: baseX, y: headY),
                    control1: CGPoint(x: cx + sign * w * 0.03, y: h * 0.46),
                    control2: CGPoint(x: baseX - sign * w * 0.13, y: headY + h * 0.01)
                )
                stroke(branch, color: drawColor, opacity: opacity)
                triangle(
                    CGPoint(x: headX, y: headY),
                    CGPoint(x: baseX, y: headY - halfH),
                    CGPoint(x: baseX, y: headY + halfH),
                    color: drawColor,
                    opacity: opacity
                )
            }
            // White turn arrow intentionally overlaps on top of the gray straight
            // arrow so the glyph matches Google/Apple lane guidance cards for
            // turn-only highlighting of straight+left / straight+right lanes.
            func turnOnlyCombined(right: Bool) {
                straightArrow(inactiveColor)
                let sign: CGFloat = right ? 1 : -1
                let branchStartY = min(h * 0.64, max(h * 0.48, bottom - h * 0.02))
                let headY = h * 0.34
                let headX = cx + sign * w * 0.35
                let baseX = headX - sign * w * (0.17 * head)
                let halfH = h * 0.080 * head
                var branch = Path()
                branch.move(to: CGPoint(x: cx, y: bottom))
                branch.addLine(to: CGPoint(x: cx, y: branchStartY))
                branch.addCurve(
                    to: CGPoint(x: baseX, y: headY),
                    control1: CGPoint(x: cx + sign * w * 0.005, y: h * 0.53),
                    control2: CGPoint(x: baseX - sign * w * 0.14, y: headY + h * 0.015)
                )
                stroke(branch, color: activeColor)
                triangle(
                    CGPoint(x: headX, y: headY),
                    CGPoint(x: baseX, y: headY - halfH),
                    CGPoint(x: baseX, y: headY + halfH),
                    color: activeColor
                )
            }

            switch style {
            case .inactive:
                switch rawValue {
                case 2: soloTurn(right: true, drawColor: inactiveColor)
                case 3: combined(right: true, drawColor: inactiveColor)
                case 4: soloTurn(right: false, drawColor: inactiveColor)
                case 5: combined(right: false, drawColor: inactiveColor)
                default: straightArrow(inactiveColor)
                }
            case .active:
                switch rawValue {
                case 2: soloTurn(right: true, drawColor: activeColor)
                case 3: combined(right: true, drawColor: activeColor)
                case 4: soloTurn(right: false, drawColor: activeColor)
                case 5: combined(right: false, drawColor: activeColor)
                default: straightArrow(activeColor)
                }
            case .turnOnlyLeft:
                turnOnlyCombined(right: false)
            case .turnOnlyRight:
                turnOnlyCombined(right: true)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Merge maneuver icon used when the source maneuver description explicitly
/// contains "merge". Lane metadata itself exposes angles but not merge semantics,
/// so we do not guess per-lane merge shapes; this graphic is source-text driven.
private struct MergeManeuverGlyph: View {
    enum Kind { case left, right, ahead }
    let kind: Kind
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height, cx = w * 0.5
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            func stroke(_ path: Path, opacity: Double = 1.0) {
                context.stroke(path, with: .color(color.opacity(opacity)), style: style)
            }
            func head(at x: CGFloat) {
                let apex = CGPoint(x: x, y: h * 0.05)
                let baseY = h * 0.23
                var p = Path()
                p.move(to: apex)
                p.addLine(to: CGPoint(x: x - w * 0.11, y: baseY))
                p.addLine(to: CGPoint(x: x + w * 0.11, y: baseY))
                p.closeSubpath()
                context.fill(p, with: .color(color))
            }
            var main = Path()
            main.move(to: CGPoint(x: cx, y: h * 0.92))
            main.addLine(to: CGPoint(x: cx, y: h * 0.23))
            stroke(main)
            head(at: cx)

            func feeder(from x: CGFloat) {
                var f = Path()
                f.move(to: CGPoint(x: x, y: h * 0.91))
                f.addCurve(
                    to: CGPoint(x: cx, y: h * 0.52),
                    control1: CGPoint(x: x, y: h * 0.73),
                    control2: CGPoint(x: cx + (x - cx) * 0.32, y: h * 0.57)
                )
                stroke(f, opacity: 0.62)
            }
            switch kind {
            case .left: feeder(from: w * 0.18)
            case .right: feeder(from: w * 0.82)
            case .ahead:
                feeder(from: w * 0.18)
                feeder(from: w * 0.82)
            }
        }
        .accessibilityHidden(true)
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
