import Foundation
import GleanCore

/// 把整条管线串起来，产出结构化结果给人看，同时把每个中间量写进日志。
@MainActor
final class AnalysisRunner: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var phase = ""
    @Published private(set) var progressLabel = ""
    @Published private(set) var progressValue: Double = 0
    @Published private(set) var groups: [AnalyzedGroup] = []
    @Published private(set) var summary: [String] = []
    @Published private(set) var logLines: [String] = []

    let logPath = GleanLog.shared.textURL.path
    private let log = GleanLog.shared

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
        summary = []
        logLines = []

        let startedAt = Date()
        let bursts = assets.filter { $0.burstID != nil }.count
        let screenshots = assets.filter(\.isScreenshot).count
        log.begin("run \(ISO8601DateFormatter().string(from: startedAt)) library=\(assets.count)")

        let sample = assets
        note("样本：\(sample.count) 张（连拍 \(bursts) · 截图 \(screenshots)）")
        log.info("scan", [
            "assets": assets.count,
            "sample": sample.count,
            "bursts": bursts,
            "screenshots": screenshots,
        ])

        let featureStarted = Date()
        phase = "计算特征"
        progressValue = 0
        let prints = await featurePrints(for: sample)
        let featureSeconds = Date().timeIntervalSince(featureStarted)
        note("特征：\(prints.count)/\(sample.count) 张，\(String(format: "%.1fs", featureSeconds))")
        log.info("features", [
            "ok": prints.count,
            "total": sample.count,
            "seconds": featureSeconds,
            "perImageMs": featureSeconds / Double(max(prints.count, 1)) * 1000,
        ])

        let analyzed = sample.filter { prints[$0.id] != nil }
        guard analyzed.count > 1 else {
            note("可分析的照片不足，先确认相册授权。")
            log.info("abort", ["reason": "not enough analyzable assets"])
            return
        }

        let byID = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })

        let sessions = SessionBuilder.build(from: analyzed)
        let sizes = sessions.map(\.count).sorted()
        let median = sizes.isEmpty ? 0 : sizes[sizes.count / 2]
        note("会话：\(sessions.count) 个（中位 \(median) 张，最大 \(sizes.last ?? 0) 张）")
        log.info("sessions", [
            "count": sessions.count,
            "median": median,
            "max": sizes.last ?? 0,
        ])

        let groupingStarted = Date()
        phase = "分组"
        progressValue = 0.7
        let raw = Grouping.groups(assets: analyzed, prints: prints)
        let photoGroups = raw.filter { $0.kind == .photo }.count
        let shotGroups = raw.filter { $0.kind == .screenshot }.count
        note("分组：照片 \(photoGroups) 组 · 截图 \(shotGroups) 组（耗时 \(String(format: "%.2fs", Date().timeIntervalSince(groupingStarted)))）")
        log.info("grouping", [
            "groups": raw.count,
            "photoGroups": photoGroups,
            "screenshotGroups": shotGroups,
        ])

        guard !raw.isEmpty else {
            note("没有发现相似组。样本小时这很正常。")
            log.info("done", ["groups": 0])
            return
        }

        var built: [AnalyzedGroup] = []
        phase = "评分"
        for (index, group) in raw.enumerated() {
            progressLabel = "\(index + 1)/\(raw.count) 组"
            progressValue = 0.75 + 0.25 * Double(index) / Double(raw.count)
            built.append(await analyze(group: group, index: index, byID: byID))
        }

        groups = built
        log.info("done", [
            "groups": built.count,
            "seconds": Date().timeIntervalSince(startedAt),
        ])
    }

    // MARK: - 单组评分

    private func analyze(
        group: Grouping.Group,
        index: Int,
        byID: [String: GleanAsset]
    ) async -> AnalyzedGroup {
        var metrics: [AssetMetrics] = []

        for assetID in group.assetIDs {
            guard let image = await ThumbnailCache.shared.image(for: assetID, target: 512) else {
                log.debug("metric.missing", ["id": assetID])
                continue
            }
            let sharpness = ImageQuality.sharpness(of: image)
            let face = ImageQuality.faceQuality(of: image)
            let asset = byID[assetID]

            var fields: [String: Any] = [
                "group": index,
                "id": assetID,
                "sharpness": Double(sharpness),
                "faces": face.faceCount,
            ]
            if let score = face.score { fields["faceQuality"] = Double(score) }
            if let asset {
                fields["name"] = asset.originalFilename ?? ""
                fields["screenshot"] = asset.isScreenshot ? 1 : 0
                fields["wh"] = "\(asset.pixelWidth)x\(asset.pixelHeight)"
            }
            log.debug("metric", fields)

            metrics.append(
                AssetMetrics(
                    assetID: assetID,
                    sharpness: sharpness,
                    faceQuality: face.score,
                    pixelCount: asset?.pixelCount ?? 0
                )
            )
        }

        let sharpnessByID = Dictionary(uniqueKeysWithValues: metrics.map { ($0.assetID, $0.sharpness) })

        let assets = KeeperRanker.rank(metrics).compactMap { keeper -> AnalyzedAsset? in
            guard let asset = byID[keeper.assetID] else { return nil }
            return AnalyzedAsset(
                id: asset.id,
                name: asset.originalFilename ?? String(asset.id.prefix(12)),
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight,
                isScreenshot: asset.isScreenshot,
                hasBurst: asset.burstID != nil,
                sharpness: sharpnessByID[keeper.assetID] ?? 0,
                faceQuality: metrics.first { $0.assetID == keeper.assetID }?.faceQuality,
                score: keeper.score,
                reason: keeper.reason
            )
        }

        return AnalyzedGroup(
            id: index,
            kind: group.kind,
            cohesion: group.cohesion,
            timeSpan: group.timeSpan,
            links: group.links,
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
            progressValue = 0.7 * Double(result.count) / Double(max(assets.count, 1))
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
