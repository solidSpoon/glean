import GrazeCore
import SwiftUI

enum Theme {
    static let cellSide: CGFloat = 168
    static let sidebarThumb: CGFloat = 52

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return shortDateFormatter.string(from: date)
    }

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
