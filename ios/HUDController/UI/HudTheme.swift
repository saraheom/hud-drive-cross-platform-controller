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

/// Reusable collapsible explanatory copy for HUD cards.
///
/// Controls and live status remain visible at all times; only secondary prose is
/// folded away. This keeps the primary driving/settings UI compact without
/// removing context when the user wants it.
struct HudDescription: View {
    let text: String
    @State private var isExpanded = true

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    Text("Details")
                        .font(.caption2.weight(.semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.bold())
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide description" : "Show description")

            if isExpanded {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
