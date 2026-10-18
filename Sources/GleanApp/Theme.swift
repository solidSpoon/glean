import GleanCore
import SwiftUI

enum Theme {
    static let cardCorner: CGFloat = 20
    static let cellSide: CGFloat = 116

    static func duration(_ interval: TimeInterval) -> String {
        if interval < 60 { return String(format: "%.0fs", interval) }
        if interval < 3600 { return String(format: "%.0fmin", interval / 60) }
        return String(format: "%.1fh", interval / 3600)
    }

    static func links(_ links: Set<Grouping.Link>) -> String {
        var parts: [String] = []
        if links.contains(.burst) { parts.append("连拍") }
        if links.contains(.visual) { parts.append("视觉") }
        if links.contains(.crossSession) { parts.append("跨会话") }
        return parts.joined(separator: "+")
    }
}

/// 液态玻璃需要一个有层次的东西在背后才有折射效果。纯色背景会让玻璃看起来像一块灰膜。
struct AppBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.09, green: 0.11, blue: 0.17),
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.accentColor.opacity(0.28), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 620
            )

            RadialGradient(
                colors: [Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.16), .clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}

/// 小的玻璃标签，用于类型徽章、日志路径这类零散信息。
struct GlassTag: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .glassEffect(
            (tint.map { Glass.regular.tint($0) } ?? .regular),
            in: .capsule
        )
    }
}
