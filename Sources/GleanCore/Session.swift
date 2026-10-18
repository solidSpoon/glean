import Foundation

/// 一次"拍摄会话"：连续的、间隔很短的一串照片。
///
/// 这是整个分组管线的第一刀。时间切片的真正价值不是"分类"，而是**把候选集从
/// 全库砍到几十张** —— 之后组内才敢用低阈值，全局阈值那套问题自然消失。
public struct PhotoSession: Sendable {
    public let assets: [GleanAsset]

    public init(assets: [GleanAsset]) {
        self.assets = assets
    }

    public var count: Int { assets.count }

    public var start: Date? { assets.first?.creationDate }
    public var end: Date? { assets.last?.creationDate }

    public var timeSpan: TimeInterval {
        guard let start, let end else { return 0 }
        return end.timeIntervalSince(start)
    }
}

public enum SessionBuilder {
    /// 相邻两张间隔超过 `maxGap` 就切开会话。
    ///
    /// 默认 300 秒（5 分钟）。原本是 90 秒，但那个值把阈值表的后两档（0.78 / 0.85）
    /// 变成了死配置——会话在 90 秒就断了，根本走不到长间隔的阈值。改成 300 秒后
    /// 0.78 那一档真正生效，且能拉回“走两步换个角度再拍”这类（隔几分钟重拍同一物）。
    ///
    /// 再往上调（比如两小时，让 0.85 也生效）风险大于收益：会话会膨胀成几百上千张，
    /// 同一房间里的不同东西都可能被 0.78–0.85 拉进一组。
    public static func build(
        from assets: [GleanAsset],
        maxGap: TimeInterval = 300
    ) -> [PhotoSession] {
        let dated = assets
            .compactMap { asset -> (GleanAsset, Date)? in
                guard let date = asset.creationDate else { return nil }
                return (asset, date)
            }
            .sorted { $0.1 < $1.1 }

        var sessions: [[GleanAsset]] = []
        var current: [GleanAsset] = []
        var previousDate: Date?

        for (asset, date) in dated {
            if let previousDate, date.timeIntervalSince(previousDate) > maxGap {
                sessions.append(current)
                current = []
            }
            current.append(asset)
            previousDate = date
        }
        if !current.isEmpty { sessions.append(current) }

        // 没有拍摄时间的资产各自独立成会话。绝不能把它们塞进同一个会话——
        // 没有时间信息时，时间不能提供任何约束，硬凑在一起只会制造误合并。
        let undated = assets
            .filter { $0.creationDate == nil }
            .map { [$0] }

        return (sessions + undated).map { PhotoSession(assets: $0) }
    }
}
