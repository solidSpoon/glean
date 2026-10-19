import Foundation

/// 分析审计：把「这一次到底凭什么把它们分成一组」写成 JSON。
///
/// 界面上只看得到组和凝聚度（组内最小两两相似度），看不到每一对具体多少分。
/// 觉得「这明显不是一组」时，靠截图和肉眼判断不了原因，得能拿到真实读数。
///
/// 每次分析写一份 `~/Library/Logs/graze/audit-<时间>.json`，只留最近 10 份。
public enum AnalysisAudit {
    /// 写盘时保留的份数。audit 一次几十 KB～几 MB，留太多没意义。
    private static let keepFiles = 10

    // MARK: - 文档结构

    public struct Step: Codable {
        public let maxGapSeconds: Double
        public let minSimilarity: Float
    }

    public struct Thresholds: Codable {
        public let photoSteps: [Step]
        public let screenshotSteps: [Step]
        public let sessionMaxGapSeconds: Double
    }

    public struct Member: Codable {
        public let id: String
        public let name: String
        public let date: String?
        /// 会话编号。照片和截图共用一套编号空间，同号即同一次「连续拍摄」。
        /// 组只会出现在单个会话内，所以这些编号理应全部相同。
        public let session: Int
    }

    public struct Pair: Codable {
        public let a: String
        public let b: String
        /// 秒数。无拍摄时间时为 -1（JSON 不能表示 inf）。
        public let secondsApart: Double
        public let similarity: Float
        /// 这一对当时比对的那道线，由间隔决定。
        public let threshold: Float
        public let pass: Bool
        /// 连拍成员：同一连拍组不参与相似度判定，pass 可能是 false。
        public let burstExempt: Bool
    }

    public struct GroupEntry: Codable {
        public let index: Int
        public let kind: String
        public let size: Int
        public let cohesion: Float
        public let timeSpanSeconds: Double
        public let latestDate: String?
        public let links: [String]
        public let members: [Member]
        public let pairs: [Pair]
        /// 组内最不像的那一对——觉得「这明显不是一回事」时先看它。
        public let weakestPair: Pair?
        public let medianSimilarity: Float?
    }

    public struct Report: Codable {
        public let generatedAt: String
        public let sample: Int
        public let groupCount: Int
        public let thresholds: Thresholds
        public let groups: [GroupEntry]
    }

    // MARK: - 生成

    public static func make(
        assets: [GrazeAsset],
        prints: [String: [Float]],
        groups: [Grouping.Group],
        policy: ThresholdPolicy = .default,
        screenshotPolicy: ThresholdPolicy = .screenshot,
        maxGap: TimeInterval = SessionBuilder.defaultMaxGap
    ) -> Report {
        // 向量归一化 + 资产索引。会话切分必须和 Grouping 里完全一致：
        // 照片和截图分开切，否则会话编号对不上，audit 就解释不了分组。
        var vectors: [String: [Float]] = [:]
        vectors.reserveCapacity(prints.count)
        for (id, values) in prints where !values.isEmpty {
            vectors[id] = Similarity.normalized(values)
        }

        var byID: [String: GrazeAsset] = [:]
        for asset in assets where vectors[asset.id] != nil { byID[asset.id] = asset }

        var sessionOf: [String: Int] = [:]
        var sessionIndex = 0
        for isScreenshot in [false, true] {
            let slice = assets.filter { $0.isScreenshot == isScreenshot && vectors[$0.id] != nil }
            for session in SessionBuilder.build(from: slice, maxGap: maxGap) {
                for asset in session.assets { sessionOf[asset.id] = sessionIndex }
                sessionIndex += 1
            }
        }

        func name(_ id: String) -> String {
            byID[id]?.originalFilename ?? String(id.prefix(12))
        }

        func similarity(_ a: String, _ b: String) -> Float {
            guard let x = vectors[a], let y = vectors[b] else { return 0 }
            return Similarity.cosine(x, y)
        }

        let entries = groups.enumerated().map { offset, group -> GroupEntry in
            let usedPolicy = group.kind == .screenshot ? screenshotPolicy : policy
            let ids = group.assetIDs.filter { byID[$0] != nil }

            let members = ids.map { id in
                Member(
                    id: id,
                    name: name(id),
                    date: byID[id]?.creationDate.map(stamp),
                    session: sessionOf[id] ?? -1
                )
            }

            var pairs: [Pair] = []
            pairs.reserveCapacity(ids.count * (ids.count - 1) / 2)
            for i in 0..<ids.count {
                for j in (i + 1)..<ids.count {
                    let a = ids[i]
                    let b = ids[j]
                    let gap = secondsBetween(byID[a]?.creationDate, byID[b]?.creationDate)
                    let value = similarity(a, b)
                    let threshold = usedPolicy.minSimilarity(forGap: gap)
                    let burstExempt = byID[a]?.burstID != nil && byID[a]?.burstID == byID[b]?.burstID
                    pairs.append(
                        Pair(
                            a: name(a),
                            b: name(b),
                            secondsApart: gap,
                            similarity: value,
                            threshold: threshold,
                            pass: burstExempt || value >= threshold,
                            burstExempt: burstExempt
                        )
                    )
                }
            }

            let sorted = pairs.map(\.similarity).sorted()

            return GroupEntry(
                index: offset,
                kind: group.kind.rawValue,
                size: ids.count,
                cohesion: group.cohesion,
                timeSpanSeconds: group.timeSpan,
                latestDate: group.latestDate.map(stamp),
                links: group.links.map(\.rawValue).sorted(),
                members: members,
                pairs: pairs,
                weakestPair: pairs.min { $0.similarity < $1.similarity },
                medianSimilarity: sorted.isEmpty ? nil : sorted[sorted.count / 2]
            )
        }

        return Report(
            generatedAt: stamp(Date()),
            sample: vectors.count,
            groupCount: groups.count,
            thresholds: Thresholds(
                photoSteps: policy.steps.map {
                    Step(maxGapSeconds: $0.maxGap, minSimilarity: $0.minSimilarity)
                },
                screenshotSteps: screenshotPolicy.steps.map {
                    Step(maxGapSeconds: $0.maxGap, minSimilarity: $0.minSimilarity)
                },
                sessionMaxGapSeconds: maxGap
            ),
            groups: entries
        )
    }

    // MARK: - 落盘

    @discardableResult
    public static func write(_ report: Report) -> URL? {
        let directory = GrazeLog.shared.directory
        let fileStamp = fileFormatter.string(from: Date())
        let url = directory.appendingPathComponent("audit-\(fileStamp).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            try encoder.encode(report).write(to: url, options: .atomic)
        } catch {
            GrazeLog.shared.debug("audit.write.failed", ["error": String(describing: error)])
            return nil
        }

        prune(in: directory)
        return url
    }

    /// 只留最近 `keepFiles` 份，免得日志目录被审计文件堆满。
    private static func prune(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        let audits = files
            .filter { $0.lastPathComponent.hasPrefix("audit-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in audits.dropFirst(keepFiles) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    // MARK: - 工具

    private static let iso = ISO8601DateFormatter()

    private static func stamp(_ date: Date) -> String { iso.string(from: date) }

    private static func secondsBetween(_ a: Date?, _ b: Date?) -> Double {
        guard let a, let b else { return -1 }
        return abs(b.timeIntervalSince(a))
    }

    private static let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
