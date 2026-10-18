import Foundation
import GleanCore

/// 三阶段：提特征 → 分组 → （按需）评分。
///
/// 评分是软加载的：全库 7624 张时评分要 187 秒，而分组只要 2 秒。没道理为了看一眼
/// 列表先等三分钟。现在分组一出来就能看到全部组，选中哪组才给哪组算清晰度和人脸。
@MainActor
final class AnalysisRunner: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var phase = ""
    @Published private(set) var progressLabel = ""
    @Published private(set) var progressValue: Double = 0

    /// 分好组的骨架，未评分。
    @Published private(set) var groups: [AnalyzedGroup] = []
    /// 已评分的组，按需填充。
    @Published private(set) var scored: [Int: AnalyzedGroup] = [:]

    @Published private(set) var summary: [String] = []
    @Published private(set) var logLines: [String] = []

    let logPath = GleanLog.shared.textURL.path
    private let log = GleanLog.shared

    private var prints: [String: [Float]] = [:]
    private var byID: [String: GleanAsset] = [:]
    private var scoring: [Int: Task<Void, Never>] = [:]

    /// 有评分结果就用评分结果，否则返回骨架。
    func group(_ id: Int) -> AnalyzedGroup? {
        scored[id] ?? groups.first { $0.id == id }
    }

    // MARK: - 主流程

    func run(assets: [GleanAsset]) async {
        guard !running else { return }
        running = true
        defer {
            running = false
            phase = ""
            progressLabel = ""
            progressValue = 0
        }

        groups = []
        scored = [:]
        scoring = [:]
        summary = []
        logLines = []

        let startedAt = Date()
        let bursts = assets.filter { $0.burstID != nil }.count
        let screenshots = assets.filter(\.isScreenshot).count
        log.begin("run \(ISO8601DateFormatter().string(from: startedAt)) library=\(assets.count)")

        note("样本：\(assets.count) 张（连拍 \(bursts) · 截图 \(screenshots)）")
        log.info("scan", [
            "sample": assets.count,
            "bursts": bursts,
            "screenshots": screenshots,
        ])

        phase = "计算特征"
        progressValue = 0
        let featureStarted = Date()
        prints = await featurePrints(for: assets)
        let featureSeconds = Date().timeIntervalSince(featureStarted)
        note("特征：\(prints.count)/\(assets.count) 张，\(String(format: "%.1fs", featureSeconds))")
        log.info("features", [
            "ok": prints.count,
            "total": assets.count,
            "seconds": featureSeconds,
            "perImageMs": featureSeconds / Double(max(prints.count, 1)) * 1000,
        ])

        let analyzed = assets.filter { prints[$0.id] != nil }
        guard analyzed.count > 1 else {
            note("可分析的照片不足，先确认相册授权。")
            log.info("abort", ["reason": "not enough analyzable assets"])
            return
        }

        byID = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })

        let sessions = SessionBuilder.build(from: analyzed)
        let sizes = sessions.map(\.count).sorted()
        let median = sizes.isEmpty ? 0 : sizes[sizes.count / 2]
        note("会话：\(sessions.count) 个（中位 \(median) 张，最大 \(sizes.last ?? 0) 张）")
        log.info("sessions", ["count": sessions.count, "median": median, "max": sizes.last ?? 0])

        phase = "分组"
        progressValue = 0.97
        let groupingStarted = Date()
        let raw = Grouping.groups(assets: analyzed, prints: prints)
        note("分组：\(raw.count) 组 ≥2 张（耗时 \(String(format: "%.2fs", Date().timeIntervalSince(groupingStarted)))）")
        log.info("grouping", [
            "groups": raw.count,
            "photoGroups": raw.filter { $0.kind == .photo }.count,
            "screenshotGroups": raw.filter { $0.kind == .screenshot }.count,
        ])

        guard !raw.isEmpty else {
            note("没有发现相似组。样本小时这很正常。")
            log.info("done", ["groups": 0])
            return
        }

        groups = raw.enumerated().map { offset, group in
            skeleton(group, index: offset)
        }

        progressValue = 1
        log.info("done", [
            "groups": groups.count,
            "seconds": Date().timeIntervalSince(startedAt),
        ])
    }

    // MARK: - 按需评分

    func ensureScored(_ groupID: Int) async {
        if scored[groupID] != nil { return }
        if let existing = scoring[groupID] {
            await existing.value
            return
        }
        guard let base = groups.first(where: { $0.id == groupID }) else { return }

        let task = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            if let value = await self.computeScore(for: base) {
                self.scored[groupID] = value
                self.log.debug("scored", [
                    "group": groupID,
                    "assets": value.assets.count,
                    "ms": Date().timeIntervalSince(started) * 1000,
                ])
            }
            self.scoring[groupID] = nil
        }
        scoring[groupID] = task
        await task.value
    }

    private func computeScore(for base: AnalyzedGroup) async -> AnalyzedGroup? {
        var metrics: [AssetMetrics] = []

        for asset in base.assets {
            guard let image = await ThumbnailCache.shared.image(for: asset.id, target: 512) else {
                log.debug("metric.missing", ["id": asset.id])
                continue
            }
            let sharpness = ImageQuality.sharpness(of: image)
            let face = ImageQuality.faceQuality(of: image)
            metrics.append(
                AssetMetrics(
                    assetID: asset.id,
                    sharpness: sharpness,
                    faceQuality: face.score,
                    pixelCount: asset.pixelCount
                )
            )
            log.debug("metric", [
                "group": base.id,
                "id": asset.id,
                "name": asset.name,
                "sharpness": Double(sharpness),
                "faces": face.faceCount,
                "faceQuality": face.score.map { Double($0) } ?? NSNull(),
                "screenshot": asset.isScreenshot ? 1 : 0,
                "wh": "\(asset.pixelWidth)x\(asset.pixelHeight)",
            ])
        }

        let ranked = KeeperRanker.rank(metrics)
        guard let keeper = ranked.first else { return nil }

        let keeperVector = prints[keeper.assetID].map { Similarity.normalized($0) }
        let metricsByID = Dictionary(uniqueKeysWithValues: metrics.map { ($0.assetID, $0) })

        let assets = ranked.compactMap { entry -> AnalyzedAsset? in
            guard let asset = byID[entry.assetID] else { return nil }

            var similarity: Float?
            if let keeperVector, let vector = prints[entry.assetID] {
                similarity = Similarity.cosine(keeperVector, Similarity.normalized(vector))
            }

            return AnalyzedAsset(
                id: asset.id,
                name: asset.originalFilename ?? String(asset.id.prefix(12)),
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate,
                isScreenshot: asset.isScreenshot,
                hasBurst: asset.burstID != nil,
                isFavorite: asset.isFavorite,
                isLivePhoto: asset.isLivePhoto,
                isPanorama: asset.isPanorama,
                isHDR: asset.isHDR,
                isDepthEffect: asset.isDepthEffect,
                latitude: asset.latitude,
                longitude: asset.longitude,
                sharpness: metricsByID[entry.assetID]?.sharpness ?? 0,
                faceQuality: metricsByID[entry.assetID]?.faceQuality,
                similarityToKeeper: similarity,
                score: entry.score,
                reason: entry.reason
            )
        }

        return AnalyzedGroup(
            id: base.id,
            kind: base.kind,
            cohesion: base.cohesion,
            timeSpan: base.timeSpan,
            links: base.links,
            isScored: true,
            assets: assets
        )
    }

    // MARK: - 骨架

    private func skeleton(_ group: Grouping.Group, index: Int) -> AnalyzedGroup {
        let assets = group.assetIDs.compactMap { id -> AnalyzedAsset? in
            guard let asset = byID[id] else { return nil }
            return AnalyzedAsset(
                id: asset.id,
                name: asset.originalFilename ?? String(asset.id.prefix(12)),
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                creationDate: asset.creationDate,
                modificationDate: asset.modificationDate,
                isScreenshot: asset.isScreenshot,
                hasBurst: asset.burstID != nil,
                isFavorite: asset.isFavorite,
                isLivePhoto: asset.isLivePhoto,
                isPanorama: asset.isPanorama,
                isHDR: asset.isHDR,
                isDepthEffect: asset.isDepthEffect,
                latitude: asset.latitude,
                longitude: asset.longitude,
                sharpness: 0,
                faceQuality: nil,
                similarityToKeeper: nil,
                score: 0,
                reason: ""
            )
        }
        return AnalyzedGroup(
            id: index,
            kind: group.kind,
            cohesion: group.cohesion,
            timeSpan: group.timeSpan,
            links: group.links,
            isScored: false,
            assets: assets
        )
    }

    // MARK: - 特征提取

    private func featurePrints(for assets: [GleanAsset]) async -> [String: [Float]] {
        var result: [String: [Float]] = [:]
        let chunkSize = 8
        var index = 0

        while index < assets.count {
            let upper = min(index + chunkSize, assets.count)
            let chunk = Array(assets[index..<upper])

            let partial = await withTaskGroup(of: (String, [Float])?.self) { group in
                for asset in chunk {
                    group.addTask {
                        guard let image = await Thumbnailer.image(for: asset.id) else {
                            GleanLog.shared.debug("thumbnail.missing", ["id": asset.id])
                            return nil
                        }
                        do {
                            return (asset.id, try FeaturePrintService.vector(for: image))
                        } catch {
                            GleanLog.shared.debug("feature.failed", [
                                "id": asset.id,
                                "error": String(describing: error),
                            ])
                            return nil
                        }
                    }
                }
                var collected: [(String, [Float])] = []
                for await item in group {
                    if let item { collected.append(item) }
                }
                return collected
            }

            for (id, vector) in partial { result[id] = vector }
            index = upper
            progressLabel = "\(result.count)/\(assets.count)"
            progressValue = 0.95 * Double(result.count) / Double(max(assets.count, 1))
        }
        return result
    }

    // MARK: - 输出

    private func note(_ line: String) {
        summary.append(line)
        logLines.append(line)
        log.info("note", ["text": line])
    }
}
