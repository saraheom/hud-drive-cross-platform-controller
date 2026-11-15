import Foundation
import UIKit
import CoreGraphics

/// Experimental *image-space* extraction of a strongly highlighted, warm-colored
/// route from a CarPlay raster. This is not map matching or route geometry.
/// No detected route -> nil, so the caller retains the existing Dark HUD image.
/// In particular, never create an invented route from navigation maneuvers.
enum HudRouteSpotlightProcessor {
    private static let cache: NSCache<UIImage, UIImage> = {
        let value = NSCache<UIImage, UIImage>()
        value.countLimit = 6
        return value
    }()

    static func render(_ image: UIImage) -> UIImage? {
        if let result = cache.object(forKey: image) { return result }
        guard let cgImage = image.cgImage, cgImage.width > 0, cgImage.height > 0 else { return nil }
        let width = min(320, cgImage.width)
        let height = max(1, Int((Double(cgImage.height) * Double(width) / Double(cgImage.width)).rounded()))
        guard height >= 48, height <= 512 else { return nil }
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: space, bitmapInfo: bitmapInfo) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        // A conservative route-color candidate, not arbitrary contrast:
        // warm-yellow first, then a stricter blue candidate for daylight maps.
        // Ambiguous components must never produce fabricated route geometry.
        let count = width * height
        var warmCandidate = [Bool](repeating: false, count: count)
        var blueCandidate = [Bool](repeating: false, count: count)
        for idx in 0..<count {
            let off = idx * 4
            let r = Int(rgba[off]), g = Int(rgba[off + 1]), b = Int(rgba[off + 2])
            warmCandidate[idx] = r >= 120 && g >= 80 && b <= 155 &&
                (r - b) >= 38 && (g - b) >= 25 && abs(r - g) <= 110
            // Common *daytime* navigation routes use saturated blue. This is a
            // secondary, stricter option because dark maps may contain other
            // blue roads. Component shape/position must still pass below.
            blueCandidate[idx] = b >= 135 && g >= 62 &&
                (b - r) >= 45 && (b - g) >= 31 && (b - r) >= (g - r)
        }

        // Select an elongated connected component near the navigation-map
        // center. A few isolated traffic lights, road labels and badges are not
        // enough to assert that we found an actual route.
        var best = [Int]()
        // Warm first for night/traffic-dark maps; then blue for daylight routes.
        // Never combine the two masks into a single road network.
        for candidate in [warmCandidate, blueCandidate] {
            var visited = [Bool](repeating: false, count: count)
            var bestScore = -1.0
            for seed in 0..<count where candidate[seed] && !visited[seed] {
            var stack = [seed]
            visited[seed] = true
            var component = [Int]()
            var lowX = width, highX = 0, lowY = height, highY = 0
            var nearCenter = false
            while let pos = stack.popLast() {
                component.append(pos)
                let x = pos % width, y = pos / width
                lowX = min(lowX, x); highX = max(highX, x)
                lowY = min(lowY, y); highY = max(highY, y)
                if x >= width / 5 && x <= 4 * width / 5 &&
                    y >= height / 3 && y <= 9 * height / 10 { nearCenter = true }
                for oy in -1...1 {
                    for ox in -1...1 where ox != 0 || oy != 0 {
                        let nx = x + ox, ny = y + oy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let next = ny * width + nx
                        if candidate[next] && !visited[next] {
                            visited[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            let spanX = highX - lowX + 1, spanY = highY - lowY + 1
            guard nearCenter, component.count >= 24,
                  max(spanX, spanY) >= 19,
                  Double(component.count) < Double(count) * 0.13 else { continue }
            let elongation = Double(max(spanX, spanY)) / Double(max(1, min(spanX, spanY)))
            guard elongation >= 1.6 else { continue }
            let score = Double(component.count) + Double(max(spanX, spanY)) * 2
            if score > bestScore { best = component; bestScore = score }
            }
            if !best.isEmpty { break }
        }
        guard !best.isEmpty else { return nil }

        // Opaque black map with a 1px electric-cyan route for HUD legibility.
        // This affects only the source-map layer, never speed/music/turn overlays.
        var output = [UInt8](repeating: 0, count: rgba.count)
        for index in 0..<count { output[index * 4 + 3] = 255 }
        for index in best {
            let x = index % width, y = index / width
            for oy in -1...1 {
                for ox in -1...1 {
                    let nx = x + ox, ny = y + oy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let off = (ny * width + nx) * 4
                    // Dim halo around the detected path.
                    output[off + 1] = max(output[off + 1], 78)
                    output[off + 2] = max(output[off + 2], 112)
                }
            }
            let off = index * 4
            output[off] = 120
            output[off + 1] = 235
            output[off + 2] = 255
        }
        let created: CGImage? = output.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: space, bitmapInfo: bitmapInfo) else { return nil }
            return ctx.makeImage()
        }
        guard let created else { return nil }
        let result = UIImage(cgImage: created, scale: 1, orientation: .up)
        cache.setObject(result, forKey: image)
        return result
    }
}
