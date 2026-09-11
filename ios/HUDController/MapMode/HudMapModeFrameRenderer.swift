import Foundation
import SwiftUI
import UIKit

@MainActor
enum HudMapModeFrameRenderer {
    static func jpeg(
        snapshot: HudMapModeSnapshot,
        settings: HudMapModeSettings,
        sourceMapImage: UIImage?,
        suppressCustomSpeedForNativeOBDProbe: Bool
    ) -> Data? {
        let content = HudMapModeCanvas(
            snapshot: snapshot,
            settings: settings,
            sourceMapImage: sourceMapImage,
            previewLanePlaceholder: false,
            suppressCustomSpeedForNativeOBDProbe: suppressCustomSpeedForNativeOBDProbe
        )
        .frame(width: 480, height: 240)
        .background(Color.black)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1.0
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return nil }
        return image.jpegData(compressionQuality: 0.82)
    }
}
