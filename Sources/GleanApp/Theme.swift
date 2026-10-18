import GleanCore
import SwiftUI

enum Theme {
    static let cellSide: CGFloat = 220
    static let sidebarThumb: CGFloat = 52

    static func duration(_ interval: TimeInterval) -> String {
        if interval < 60 { return String(format: "%.0f 秒", interval) }
        if interval < 3600 { return String(format: "%.0f 分", interval / 60) }
        return String(format: "%.1f 小时", interval / 3600)
    }

    static func links(_ links: Set<Grouping.Link>) -> String {
        var parts: [String] = []
        if links.contains(.burst) { parts.append("连拍") }
        if links.contains(.visual) { parts.append("视觉") }
        if links.contains(.crossSession) { parts.append("跨会话") }
        return parts.joined(separator: "+")
    }
}
