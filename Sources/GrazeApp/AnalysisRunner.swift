import Foundation
import GrazeCore

/// 两阶段：提特征 → 分组。分组完成即全部完成。
///
/// 早期还做过第三阶段「组内评分」（拉普拉斯清晰度 + 人脸质量，用来推荐保留哪张），
/// 每次全库要 187 秒。这个工具只负责把重复的挑成一堆，哪张该留人自己看比算法准，
/// 所以那一层整个拆掉了——现在全库 7624 张从点「分析」到出列表约 41 秒。
@MainActor
final class AnalysisRunner: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var scanning = false
    @Published private(set) var scanDone = 0
    @Published private(set) var scanTotal = 0
    @Published private(set) var phase = ""
    @Published private(set) var progressLabel = ""
    @Published private(set) var progressValue: Double = 0

    @Published private(set) var groups: [AnalyzedGroup] = []

    /// 本次运行的阶段小结，按发生顺序。状态栏只显示最后一条，
    /// 完整内容在日志文件里。
    @Published private(set) var summary: [String] = []

    private let log = GrazeLog.shared

    private var prints: [String: [Float]] = [:]
    private var byID: [String: GrazeAsset] = [:]

    func group(_ id: Int) -> AnalyzedGroup? {
        groups.first { $0.id == id }
    }

    // MARK: - 读取相册

    /// 必须跑在后台线程。
    ///
    /// `PHFetchResult.enumerateObjects` + `PHAssetResource.assetResources(for:)` 是
    /// 同步阻塞调用，如果在主线程跑（`Task {}` 在 @MainActor 方法里会继承主线程），
    /// 界面会整个冻住，进度条一次都刷不出来。
    func scanLibrary() async -> [GrazeAsset] {
        guard !scanning else { return [] }
        scanning = true
        scanDone = 0
        scanTotal = 0
        defer { scanning = false }

        let started = Date()
        let loaded = await Task.detached(priority: .userInitiated) { [self] in
            LibraryScanner.loadAssets { done, total in
                Task { @MainActor in
                    // 进度回调来自后台线程，必须回主线程改 @Published
                    self.scanDone = done
                    self.scanTotal = total
                }
            }
        }.value

        let seconds = Date().timeIntervalSince(started)
        log.info("scan.done", [
            "assets": loaded.count,
            "seconds": seconds,
            "perAssetMs": seconds / Double(max(loaded.count, 1)) * 1000,
        ])
        return loaded
    }

    // MARK: - 主流程

    func run(assets: [GrazeAsset]) async {
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

        // 缓存按「id + 修改时间 + 尺寸」命中，只有新图 / 改过的图才真的过一遍 Vision。
        let cache = FeatureCache.shared
        let (cached, pending) = cache.partition(assets)
        prints = cached
        var computed: [String: [Float]] = [:]
        var inCloudSkipped = 0
        if !pending.isEmpty {
            let outcome = await featurePrints(for: pending, completedBefore: cached.count, total: assets.count)
            computed = outcome.prints
            inCloudSkipped = outcome.inCloud
            prints.merge(computed) { _, new in new }
            cache.store(computed, for: pending)
        }
        cache.save()

        let featureSeconds = Date().timeIntervalSince(featureStarted)
        var featureLine = "特征：\(prints.count)/\(assets.count) 张（缓存命中 \(cached.count)，新算 \(computed.count)"
        // 仅存于 iCloud 的照片拿不到图，也就不进分组。这是有意为之（不批量下载整个云端图库），
        // 但必须说出来，否则就是“为什么这张没被找出来”的无声黑洞。
        if inCloudSkipped > 0 {
            featureLine += "，仅存于 iCloud 跳过 \(inCloudSkipped)"
        }
        featureLine += "），\(String(format: "%.1fs", featureSeconds))"
        note(featureLine)
        log.info("features", [
            "ok": prints.count,
            "total": assets.count,
            "cached": cached.count,
            "computed": computed.count,
            "inCloudSkipped": inCloudSkipped,
            "seconds": featureSeconds,
            "perImageMs": featureSeconds / Double(max(computed.count, 1)) * 1000,
        ])

        let analyzed = assets.filter { prints[$0.id] != nil }
        guard analyzed.count > 1 else {
            note("可分析的照片不足，先确认相册授权。")
            log.info("abort", ["reason": "not enough analyzable assets"])
            return
        }

        byID = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })

        // 聚类时照片和截图是分开切会话的，所以这里也要分开统计，
        // 否则报出来的「中位/最大」跟真正参与比较的会话对不上。
        let photoSessions = SessionBuilder.build(from: analyzed.filter { !$0.isScreenshot })
        let shotSessions = SessionBuilder.build(from: analyzed.filter(\.isScreenshot))
        for (label, sessions) in [("照片", photoSessions), ("截图", shotSessions)] {
            let sizes = sessions.map(\.count).sorted()
            let median = sizes.isEmpty ? 0 : sizes[sizes.count / 2]
            note("会话（\(label)）：\(sessions.count) 个（中位 \(median) 张，最大 \(sizes.last ?? 0) 张）")
            log.info("sessions", [
                "kind": label,
                "count": sessions.count,
                "median": median,
                "max": sizes.last ?? 0,
            ])
        }

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

        // 审计默认就写，不用开关：「为什么这两张被分成一组」是事后唯一能查的证据，
        // 等出问题再补就打不出当时的结果了。编码 + 落盘放后台，不堵界面。
        let auditReport = AnalysisAudit.make(assets: analyzed, prints: prints, groups: raw)
        Task.detached(priority: .utility) {
            if let url = AnalysisAudit.write(auditReport) {
                GrazeLog.shared.info("audit", ["path": url.path, "groups": auditReport.groupCount])
            }
        }

        guard !raw.isEmpty else {
            note("没有发现相似组。样本小时这很正常。")
            log.info("done", ["groups": 0])
            return
        }

        groups = raw.enumerated().map { offset, group in
            makeGroup(group, index: offset)
        }

        progressValue = 1
        log.info("done", [
            "groups": groups.count,
            "seconds": Date().timeIntervalSince(startedAt),
        ])
    }

    // MARK: - 组装

    /// 把分组结果变成 UI 用的结构。
    ///
    /// 组内按拍摄时间正序排列——没有"推荐保留"之后，时间就是唯一有意义的顺序。
    /// 顺带算一下每张与组内其他成员的相似度区间，纯展示用。
    private func makeGroup(_ group: Grouping.Group, index: Int) -> AnalyzedGroup {
        let ids = group.assetIDs
            .filter { byID[$0] != nil }
            .sorted { (byID[$0]?.creationDate ?? .distantPast) < (byID[$1]?.creationDate ?? .distantPast) }

        var vectors: [String: [Float]] = [:]
        for id in ids {
            if let vector = prints[id] {
                vectors[id] = Similarity.normalized(vector)
            }
        }

        let assets = ids.compactMap { id -> AnalyzedAsset? in
            guard let asset = byID[id] else { return nil }

            var lower: Float?
            var upper: Float?
            if let mine = vectors[id] {
                for other in ids where other != id {
                    guard let theirs = vectors[other] else { continue }
                    let value = Similarity.cosine(mine, theirs)
                    lower = lower.map { min($0, value) } ?? value
                    upper = upper.map { max($0, value) } ?? value
                }
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
                similarityMin: lower,
                similarityMax: upper
            )
        }

        return AnalyzedGroup(
            id: index,
            kind: group.kind,
            cohesion: group.cohesion,
            timeSpan: group.timeSpan,
            latestDate: group.latestDate,
            links: group.links,
            assets: assets
        )
    }

    // MARK: - 特征提取

    /// 一批特征的结果。除了向量，还带回「多少张因为只在 iCloud 而拿不到图」——
    /// 这个数字必须报出来，否则就是“为什么这张没被找出来”的无声黑洞。
    private struct FeatureBatch {
        var prints: [String: [Float]] = [:]
        var inCloud = 0
    }

    private func featurePrints(
        for assets: [GrazeAsset],
        completedBefore: Int,
        total: Int
    ) async -> FeatureBatch {
        var batch = FeatureBatch()
        let chunkSize = 8
        var index = 0

        while index < assets.count {
            let upper = min(index + chunkSize, assets.count)
            let chunk = Array(assets[index..<upper])

            // 这里刻意不允许联网：批量提特征时把整个云端图库拉下来不是用户点「分析」时的预期。
            let partial = await withTaskGroup(of: (id: String, vector: [Float]?, inCloud: Bool).self) { group in
                for asset in chunk {
                    group.addTask {
                        let outcome = await Thumbnailer.load(
                            for: asset.id,
                            targetSize: CGSize(width: 512, height: 512),
                            allowNetwork: false
                        )
                        guard let image = outcome.image else {
                            GrazeLog.shared.debug("thumbnail.missing", [
                                "id": asset.id,
                                "inCloud": outcome.isInCloud,
                            ])
                            return (asset.id, nil, outcome.isInCloud)
                        }
                        do {
                            return (asset.id, try FeaturePrintService.vector(for: image), false)
                        } catch {
                            GrazeLog.shared.debug("feature.failed", [
                                "id": asset.id,
                                "error": String(describing: error),
                            ])
                            return (asset.id, nil, false)
                        }
                    }
                }
                var collected: [(id: String, vector: [Float]?, inCloud: Bool)] = []
                for await item in group { collected.append(item) }
                return collected
            }

            for item in partial {
                if let vector = item.vector {
                    batch.prints[item.id] = vector
                } else if item.inCloud {
                    batch.inCloud += 1
                }
            }
            index = upper
            let done = completedBefore + batch.prints.count
            progressLabel = "\(done)/\(total)"
            progressValue = 0.95 * Double(done) / Double(max(total, 1))
        }
        return batch
    }

    // MARK: - 输出

    private func note(_ line: String) {
        summary.append(line)
        log.info("note", ["text": line])
    }
}
