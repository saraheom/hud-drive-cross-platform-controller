import SwiftUI

enum HudTheme {
    static let background = Color(red: 0.07, green: 0.075, blue: 0.085)
    static let card = Color(red: 0.18, green: 0.18, blue: 0.18)
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.34)
}

struct HudCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding()
            .background(HudTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
