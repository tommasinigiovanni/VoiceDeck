import SwiftUI

/// Shared visual language with ModelDeck, including native light and dark appearances.
enum Palette {
    private static func adaptive(_ dark: NSColor, _ light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let accent = adaptive(.init(red: 0.40, green: 0.88, blue: 0.72, alpha: 1), .init(red: 0.08, green: 0.45, blue: 0.34, alpha: 1))
    static let blue = adaptive(.init(red: 0.46, green: 0.68, blue: 0.99, alpha: 1), .init(red: 0.16, green: 0.36, blue: 0.74, alpha: 1))
    static let amber = adaptive(.init(red: 0.96, green: 0.72, blue: 0.38, alpha: 1), .init(red: 0.62, green: 0.37, blue: 0.06, alpha: 1))
    static let background = adaptive(.init(red: 0.055, green: 0.071, blue: 0.085, alpha: 1), .init(red: 0.95, green: 0.96, blue: 0.97, alpha: 1))
    static let sidebar = adaptive(.init(red: 0.048, green: 0.062, blue: 0.075, alpha: 1), .init(red: 0.84, green: 0.85, blue: 0.86, alpha: 1))
    static let card = adaptive(.init(red: 0.085, green: 0.105, blue: 0.121, alpha: 1), .white)
    static let ink = Color(nsColor: .labelColor)
    static let subtle = adaptive(.white, .black)
    static let speakerColors: [Color] = [accent, blue, .orange, .purple, .pink, .teal, .brown, .green]
    static func speaker(_ id: String?, in ids: [String]) -> Color {
        guard let id, let index = ids.firstIndex(of: id) else { return .secondary }
        return speakerColors[index % speakerColors.count]
    }
}

struct StatusBadge: View {
    let text: String
    var color: Color = Palette.accent
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(0.10), in: Capsule())
    }
}

extension View {
    func voiceDeckCard(radius: CGFloat = 18) -> some View {
        background(Palette.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Palette.subtle.opacity(0.065), lineWidth: 1))
    }
}
