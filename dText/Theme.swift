import SwiftUI

enum Theme {
    static let accent = Color(red: 0.16, green: 0.53, blue: 0.43)
    static let canvas = Color(nsColor: .textBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.08)
    static func color(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "purple": .purple
        case "orange": .orange
        case "pink": .pink
        default: accent
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27).fill(Theme.accent.gradient)
            Text("d").font(.system(size: size * 0.78, weight: .semibold, design: .rounded))
                .foregroundStyle(.white).offset(y: -size * 0.04)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.8))
                .frame(width: 2, height: size * 0.42).offset(x: size * 0.26, y: size * 0.04)
        }.frame(width: size, height: size)
    }
}

struct Keycap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 3)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }
}

struct SectionCaption: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold))
            .tracking(1.3).foregroundStyle(.secondary)
    }
}

extension Notification.Name {
    static let newSnippet = Notification.Name("dText.newSnippet")
    static let newSet = Notification.Name("dText.newSet")
    static let quickSearch = Notification.Name("dText.quickSearch")
    static let showGuide = Notification.Name("dText.showGuide")
}
