import Foundation

/// 一次"拍摄会话"：连续的、间隔很短的一串照片。
///
/// 这是整个分组管线的第一刀。时间切片的真正价值不是"分类"，而是**把候选集从
/// 全库砍到几十张** —— 之后组内才敢用低阈值，全局阈值那套问题自然消失。
public struct PhotoSession: Sendable {
    public let assets: [GrazeAsset]

    public init(assets: [GrazeAsset]) {
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
    /// 会话切分阈值：300 秒（5 分钟）。
    ///
    /// 原本是 90 秒，但那个值把 `ThresholdPolicy` 里长间隔的几档变成了死配置——
    /// 会话在 90 秒就断了，根本走不到那几档。调到 300 秒后 `≤5min → 0.78` 才真正生效。
    ///
    /// 再往上调（比如两小时，让 0.85 也生效）风险大于收益：会话会膨胀成几百上千张，
    /// 同一房间里的不同东西都可能被 0.78–0.85 拉进一组。
    ///
    /// 只在这里定义一次，`Grouping.groups` 的默认值引用它，免得两处各写一个数。
    public static let defaultMaxGap: TimeInterval = 300

    /// 相邻两张间隔超过 `maxGap` 就切开会话。
    public static func build(
        from assets: [GrazeAsset],
        maxGap: TimeInterval = defaultMaxGap
    ) -> [PhotoSession] {
        let dated = assets
            .compactMap { asset -> (GrazeAsset, Date)? in
                guard let date = asset.creationDate else { return nil }
                return (asset, date)
            }
            .sorted { $0.1 < $1.1 }

        var sessions: [[GrazeAsset]] = []
        var current: [GrazeAsset] = []
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
