import Foundation

/// 相似度阈值。
///
/// 三个数，都是「隔多久 → 要求多像」：
///
///   · ≤5 秒（连按、同一瞬间）→ 0.84
///   · ≤1 分钟（同一阵连拍）    → 0.90
///   · ≤5 分钟（同一场拍摄）    → 0.92
///
/// 为什么间隔越久要求越严：这组数字是从真实图库里量出来的——同一瞬间拍的两张，
/// 相似度中位数 0.956；隔 1～2 分钟的 0.899；而「同一个院子、同一个角度、换了
/// 一批人」也往往能达到 0.83～0.87。一个固定的 0.80 同时容纳了这两种东西，结果
/// 就是把不同的人湊成一组。
///
/// 刻意不再有「跨会话合并」和「成员下限」这两个东西：
/// 前者是为「改天重回同一地点」准备的，对「去重」来说是错的目标；后者挂不住链式
/// 合并（A~B、B~C 都过线但 A 与 C 差很远，整条链照样粘一起）。
public struct ThresholdPolicy: Sendable {
    public struct Step: Sendable {
        public let maxGap: TimeInterval
        public let minSimilarity: Float

        public init(maxGap: TimeInterval, minSimilarity: Float) {
            self.maxGap = maxGap
            self.minSimilarity = minSimilarity
        }
    }

    /// 按时间间隔升序排列的分段阈值。
    public var steps: [Step]

    public init(steps: [Step]) {
        self.steps = steps
    }

    public static let `default` = ThresholdPolicy(steps: [
        Step(maxGap: 5, minSimilarity: 0.84),
        Step(maxGap: 60, minSimilarity: 0.90),
        Step(maxGap: SessionBuilder.defaultMaxGap, minSimilarity: 0.92),
    ])

    /// 截图专用：比照片严格得多。
    ///
    /// 截图全是「白底 + 状态栏 + 文字」，FeaturePrint 天然给高分——实测里跨 52 小时
    /// 的两张截图能到 0.963。不收紧的话任何两张截图都会被判成相似。
    ///
    /// 这套值没有实测支撑（图库里截图样本不够），属于保守估计。
    public static let screenshot = ThresholdPolicy(steps: [
        Step(maxGap: 2, minSimilarity: 0.96),
        Step(maxGap: SessionBuilder.defaultMaxGap, minSimilarity: 0.97),
    ])

    public func minSimilarity(forGap gap: TimeInterval) -> Float {
        for step in steps where gap <= step.maxGap {
            return step.minSimilarity
        }
        // 超过最后一档：会话切分保证走不到这里，真走到了就按最严的一档处理。
        return steps.last?.minSimilarity ?? 1
    }
}

public enum Grouping {
    public enum Link: String, Sendable, Hashable {
        /// 系统给的连拍标识相同。零成本、100% 准确，不参与相似度判断。
        case burst
        /// 时间上够近且视觉上够像。
        case visual
    }

    /// 照片和截图分开聚类：它们的最佳阈值差得太多，混在一起两种都会做错。
    public enum Kind: String, Sendable, Hashable {
        case photo
        case screenshot
    }

    public struct Group: Sendable {
        public let kind: Kind
        public let assetIDs: [String]
        /// 组内最小两两相似度。除连拍成员外，每张都必须过线才进得来，所以它有下限。
        public let cohesion: Float
        public let timeSpan: TimeInterval
        /// 组内最新的拍摄时间。列表按它倒序——找图通常也是按「最近」找的。
        public let latestDate: Date?
        public let links: Set<Link>

        public var size: Int { assetIDs.count }
    }

    // MARK: - Entry

    public static func groups(
        assets: [GrazeAsset],
        prints: [String: [Float]],
        policy: ThresholdPolicy = .default,
        screenshotPolicy: ThresholdPolicy = .screenshot,
        maxGap: TimeInterval = SessionBuilder.defaultMaxGap
    ) -> [Group] {
        var vectors: [String: [Float]] = [:]
        vectors.reserveCapacity(prints.count)
        for (id, values) in prints where !values.isEmpty {
            vectors[id] = Similarity.normalized(values)
        }

        let valid = assets.filter { vectors[$0.id] != nil }
        guard valid.count > 1 else { return [] }

        let photos = cluster(
            valid.filter { !$0.isScreenshot },
            vectors: vectors,
            policy: policy,
            kind: .photo,
            maxGap: maxGap
        )
        let screenshots = cluster(
            valid.filter(\.isScreenshot),
            vectors: vectors,
            policy: screenshotPolicy,
            kind: .screenshot,
            maxGap: maxGap
        )

        // 照片组与截图组各自聚完之后合在一起，按组内最新时间倒序；
        // 时间相同的再按可信度排。
        return (photos + screenshots).sorted { lhs, rhs in
            let left = lhs.latestDate ?? .distantPast
            let right = rhs.latestDate ?? .distantPast
            if left != right { return left > right }
            if abs(lhs.cohesion - rhs.cohesion) > 0.001 { return lhs.cohesion > rhs.cohesion }
            return lhs.size > rhs.size
        }
    }

    // MARK: - 分组

    /// 会话内按「团」分组：一个组里**任意两张**都必须过线。
    ///
    /// 这是整个算法的关键。以前用并查集连边，A~B、B~C 就 A/B/C 一组，哪怕 A 与 C
    /// 只有 0.4——一条链能把整个下午的照片串成一组。现在新照片只有「和组里每一张
    /// 都够像」才进组，否则自己另起一组，滚雪球从原理上就不成立。
    private static func cluster(
        _ valid: [GrazeAsset],
        vectors: [String: [Float]],
        policy: ThresholdPolicy,
        kind: Kind,
        maxGap: TimeInterval
    ) -> [Group] {
        guard valid.count > 1 else { return [] }

        var output: [Group] = []
        // 会话仍然必要：它把候选对从「全库两两」压到「几分钟内的两两」。
        for session in SessionBuilder.build(from: valid, maxGap: maxGap) {
            guard session.assets.count > 1 else { continue }

            var buckets: [[GrazeAsset]] = []
            for asset in session.assets {
                if let index = buckets.firstIndex(where: {
                    fits(asset, into: $0, vectors: vectors, policy: policy)
                }) {
                    buckets[index].append(asset)
                } else {
                    buckets.append([asset])
                }
            }

            for bucket in buckets where bucket.count > 1 {
                output.append(makeGroup(kind: kind, members: bucket, vectors: vectors, policy: policy))
            }
        }
        return output
    }

    /// 这张能不能进这个组：和组里每一张都要过线。连拍成员豁免——
    /// 同一组连拍的帧可以是「完全不像」的两个表情，但语义上必然是同一组。
    private static func fits(
        _ asset: GrazeAsset,
        into members: [GrazeAsset],
        vectors: [String: [Float]],
        policy: ThresholdPolicy
    ) -> Bool {
        for other in members {
            if let mine = asset.burstID, mine == other.burstID { continue }
            guard let mine = asset.creationDate, let theirs = other.creationDate else { return false }
            let similarity = Similarity.cosine(vectors[asset.id]!, vectors[other.id]!)
            guard similarity >= policy.minSimilarity(forGap: abs(theirs.timeIntervalSince(mine))) else {
                return false
            }
        }
        return true
    }

    private static func makeGroup(
        kind: Kind,
        members: [GrazeAsset],
        vectors: [String: [Float]],
        policy: ThresholdPolicy
    ) -> Group {
        // 组内按拍摄时间正序：没有「推荐保留」之后，时间就是唯一有意义的顺序。
        let ordered = members.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }

        var minimum: Float = 1
        var hasBurst = false
        var hasVisual = false

        for i in 0..<ordered.count {
            for j in (i + 1)..<ordered.count {
                let a = ordered[i]
                let b = ordered[j]
                let similarity = Similarity.cosine(vectors[a.id]!, vectors[b.id]!)
                minimum = min(minimum, similarity)

                if let burst = a.burstID, burst == b.burstID {
                    hasBurst = true
                    continue
                }
                guard let left = a.creationDate, let right = b.creationDate else { continue }
                if similarity >= policy.minSimilarity(forGap: abs(right.timeIntervalSince(left))) {
                    hasVisual = true
                }
            }
        }

        let dates = ordered.compactMap(\.creationDate)
        var links: Set<Link> = []
        if hasBurst { links.insert(.burst) }
        if hasVisual { links.insert(.visual) }

        return Group(
            kind: kind,
            assetIDs: ordered.map(\.id),
            cohesion: minimum,
            timeSpan: dates.isEmpty ? 0 : dates.max()!.timeIntervalSince(dates.min()!),
            latestDate: dates.max(),
            links: links
        )
    }
}
