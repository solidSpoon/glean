import Foundation

/// 相似度阈值策略。
///
/// 核心思想：**阈值不是常数，是时间间隔的函数**。两张照片隔 1 秒还是隔 40 分钟，
/// 同样是"长得像"，可信度完全不同——1 秒前那张就是同一张，40 分钟后那张可能只是
/// 同一个景点。
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

    /// 跨会话合并（同一地点改天再去）只看视觉，用更严的阈值。
    public var crossSessionMinSimilarity: Float

    /// 组成员必须与"组代表图"达到的下限。防链式合并：A~B、B~C 都过线但 A 与 C
    /// 差很远时，把 C 剪掉，而不是让整组无限蔓延。
    public var memberFloor: Float

    public init(
        steps: [Step],
        crossSessionMinSimilarity: Float,
        memberFloor: Float
    ) {
        self.steps = steps
        self.crossSessionMinSimilarity = crossSessionMinSimilarity
        self.memberFloor = memberFloor
    }

    /// 这些数字是**起点，不是结论**，但有一半已经被实测撑住了：
    ///
    /// 合成图实测（同一张照片逐步模糊后的余弦）：2x → 0.85，4x → 0.73，8x → 0.70。
    /// 也就是说**“糊掉的那一张”——恰恰是你最想清掉的——相似度会明显下降**。
    /// 如果短间隔阈值定在 0.75，那张 4x 模糊的照片就不会进组，工具反而在最该干活的
    /// 地方漏了。所以会话内宁可爱多分组（召回升），不要漏；分了不该分的组，用户扫
    /// 一眼就能看出来，漏掉的那张永远不会自己冒出来。
    ///
    /// 真实照片上的最优值必须用 audit 曲线校准，别直接搬这几个数字上线。
    public static let `default` = ThresholdPolicy(
        steps: [
            Step(maxGap: 2, minSimilarity: 0.65),       // 连拍，几乎是同一张
            Step(maxGap: 30, minSimilarity: 0.70),      // 同一场景调整后再拍，容忍一张糊了
            Step(maxGap: 300, minSimilarity: 0.78),     // 同一机位不同尝试
            Step(maxGap: 7200, minSimilarity: 0.85),    // 离开又回来
        ],
        crossSessionMinSimilarity: 0.88,
        memberFloor: 0.55
    )

    public func minSimilarity(forGap gap: TimeInterval) -> Float {
        for step in steps where gap <= step.maxGap {
            return step.minSimilarity
        }
        return crossSessionMinSimilarity
    }
}

public enum Grouping {
    public enum Link: String, Sendable, Hashable {
        /// 系统给的连拍标识相同。零成本、100% 准确，不参与相似度判断。
        case burst
        /// 时间上够近且视觉上够像。
        case visual
        /// 跨会话被代表图拉到了一起（改天重回同一地点）。
        case crossSession
    }

    public struct Group: Sendable {
        public let assetIDs: [String]
        /// 组内最小两两相似度。这是"这组有多可信"的最直接度量。
        public let cohesion: Float
        public let timeSpan: TimeInterval
        public let links: Set<Link>

        public var size: Int { assetIDs.count }
    }

    // MARK: - Entry

    public static func groups(
        assets: [GleanAsset],
        prints: [String: [Float]],
        policy: ThresholdPolicy = .default,
        maxGap: TimeInterval = 90
    ) -> [Group] {
        var vectors: [String: [Float]] = [:]
        vectors.reserveCapacity(prints.count)
        for (id, values) in prints where !values.isEmpty {
            vectors[id] = Similarity.normalized(values)
        }

        let valid = assets.filter { vectors[$0.id] != nil }
        guard valid.count > 1 else { return [] }

        var indexOf: [String: Int] = [:]
        indexOf.reserveCapacity(valid.count)
        for (offset, asset) in valid.enumerated() { indexOf[asset.id] = offset }

        let sessions = SessionBuilder.build(from: valid, maxGap: maxGap)

        var sessionOfAsset: [String: Int] = [:]
        for (sessionIndex, session) in sessions.enumerated() {
            for asset in session.assets { sessionOfAsset[asset.id] = sessionIndex }
        }

        // 第一阶段：会话内聚类
        var components: [[Int]] = []      // 成员在 valid 中的下标
        var componentSession: [Int] = []  // 所属会话编号
        var sessionLinks: [Set<Link>] = []

        for (sessionIndex, session) in sessions.enumerated() {
            let members = session.assets.compactMap { indexOf[$0.id] }
            guard !members.isEmpty else { continue }

            let (localComponents, links) = clusterSession(
                members: members,
                assets: valid,
                vectors: vectors,
                policy: policy
            )
            for component in localComponents {
                components.append(component)
                componentSession.append(sessionIndex)
            }
            sessionLinks.append(links)
        }

        // 第二阶段：跨会话只用代表图比较
        var medoidVectors: [[Float]] = []
        for component in components {
            medoidVectors.append(vectors[valid[medoid(of: component, assets: valid, vectors: vectors)].id]!)
        }

        var crossUnion = UnionFind(count: components.count)
        if policy.crossSessionMinSimilarity > 0 {
            for i in 0..<components.count {
                for j in (i + 1)..<components.count where componentSession[i] != componentSession[j] {
                    if Similarity.cosine(medoidVectors[i], medoidVectors[j]) >= policy.crossSessionMinSimilarity {
                        crossUnion.union(i, j)
                    }
                }
            }
        }

        var merged: [Int: [Int]] = [:]
        for i in 0..<components.count {
            merged[crossUnion.find(i), default: []].append(contentsOf: components[i])
        }

        // 第三阶段：剪掉离代表图太远的成员，再组装
        var output: [Group] = []
        for (_, members) in merged {
            let pruned = prune(
                members: members,
                assets: valid,
                vectors: vectors,
                floor: policy.memberFloor
            )
            guard pruned.count >= 2 else { continue }

            let ids = pruned.map { valid[$0].id }
            let dates = pruned.compactMap { valid[$0].creationDate }
            let span = dates.isEmpty ? 0 : (dates.max()!.timeIntervalSince(dates.min()!))
            output.append(
                Group(
                    assetIDs: ids,
                    cohesion: minPairwiseSimilarity(pruned, vectors: vectors, valid: valid),
                    timeSpan: span,
                    links: links(for: pruned, assets: valid, vectors: vectors, policy: policy, sessionOfAsset: sessionOfAsset)
                )
            )
        }

        return output.sorted {
            if abs($0.cohesion - $1.cohesion) > 0.001 { return $0.cohesion > $1.cohesion }
            return $0.size > $1.size
        }
    }

    // MARK: - Session clustering

    private static func clusterSession(
        members: [Int],
        assets: [GleanAsset],
        vectors: [String: [Float]],
        policy: ThresholdPolicy
    ) -> (components: [[Int]], links: Set<Link>) {
        var union = UnionFind(count: members.count)
        var links: Set<Link> = []

        for i in 0..<members.count {
            for j in (i + 1)..<members.count {
                let a = assets[members[i]]
                let b = assets[members[j]]

                // 连拍标识优先，完全不看相似度。同一组连拍的帧可能是"完全不像"的
                // 两个表情，但它们在语义上必然是同一组。
                if let burst = a.burstID, burst == b.burstID {
                    union.union(i, j)
                    links.insert(.burst)
                    continue
                }

                guard let da = a.creationDate, let db = b.creationDate else { continue }
                let gap = abs(db.timeIntervalSince(da))
                let similarity = Similarity.cosine(vectors[a.id]!, vectors[b.id]!)
                if similarity >= policy.minSimilarity(forGap: gap) {
                    union.union(i, j)
                    links.insert(.visual)
                }
            }
        }

        var buckets: [Int: [Int]] = [:]
        for i in 0..<members.count {
            buckets[union.find(i), default: []].append(members[i])
        }
        return (Array(buckets.values), links)
    }

    // MARK: - Helpers

    /// 组代表图：到组内其他成员相似度之和最大的那个。
    private static func medoid(
        of members: [Int],
        assets: [GleanAsset],
        vectors: [String: [Float]]
    ) -> Int {
        guard members.count > 1 else { return members[0] }
        var best = members[0]
        var bestScore: Float = -.greatestFiniteMagnitude
        for candidate in members {
            var score: Float = 0
            for other in members where other != candidate {
                score += Similarity.cosine(vectors[assets[candidate].id]!, vectors[assets[other].id]!)
            }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    /// 剪枝。但连拍成员豁免——它们的相似度低是正常的（表情变了），不是误合并。
    private static func prune(
        members: [Int],
        assets: [GleanAsset],
        vectors: [String: [Float]],
        floor: Float
    ) -> [Int] {
        guard members.count > 2 else { return members }
        let center = medoid(of: members, assets: assets, vectors: vectors)
        let centerVector = vectors[assets[center].id]!
        let burstIDs = Set(members.compactMap { assets[$0].burstID })

        return members.filter { member in
            if member == center { return true }
            let similarity = Similarity.cosine(centerVector, vectors[assets[member].id]!)
            if similarity >= floor { return true }
            // 连拍豁免：只要组里存在同 burst 的伙伴，就不剪
            if let burst = assets[member].burstID, burstIDs.contains(burst) { return true }
            return false
        }
    }

    private static func minPairwiseSimilarity(
        _ members: [Int],
        vectors: [String: [Float]],
        valid: [GleanAsset]
    ) -> Float {
        guard members.count > 1 else { return 1 }
        var minimum: Float = 1
        for i in 0..<members.count {
            for j in (i + 1)..<members.count {
                let similarity = Similarity.cosine(
                    vectors[valid[members[i]].id]!,
                    vectors[valid[members[j]].id]!
                )
                minimum = min(minimum, similarity)
            }
        }
        return minimum
    }

    private static func links(
        for members: [Int],
        assets: [GleanAsset],
        vectors: [String: [Float]],
        policy: ThresholdPolicy,
        sessionOfAsset: [String: Int]
    ) -> Set<Link> {
        var result: Set<Link> = []
        for i in 0..<members.count {
            for j in (i + 1)..<members.count {
                let a = assets[members[i]]
                let b = assets[members[j]]
                if let burst = a.burstID, burst == b.burstID {
                    result.insert(.burst)
                    continue
                }
                guard let da = a.creationDate, let db = b.creationDate else { continue }
                let gap = abs(db.timeIntervalSince(da))
                let similarity = Similarity.cosine(vectors[a.id]!, vectors[b.id]!)
                guard similarity >= policy.minSimilarity(forGap: gap) else { continue }
                if sessionOfAsset[a.id] != sessionOfAsset[b.id] {
                    result.insert(.crossSession)
                } else {
                    result.insert(.visual)
                }
            }
        }
        return result
    }
}
