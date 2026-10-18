import Foundation
import GleanCore

/// 把整条管线串起来跑一遍，产出人可读的报告。
/// 现在它是"验证器"，之后会被拆成后台批处理 + 增量缓存。
@MainActor
final class AnalysisRunner: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var progress = ""
    @Published private(set) var report: [String] = []

    func run(assets: [GleanAsset], limit: Int = 300, topGroups: Int = 6) async {
        guard !running else { return }
        running = true
        defer {
            running = false
            progress = ""
        }

        report = []
        let sample = Array(assets.prefix(limit))
        log("样本：最近 \(sample.count) 张（全库 \(assets.count) 张）")

        let started = Date()
        let prints = await featurePrints(for: sample)
        log("特征：\(prints.count)/\(sample.count) 张，\(seconds(since: started))")

        let analyzed = sample.filter { prints[$0.id] != nil }
        guard analyzed.count > 1 else {
            log("可分析的照片不足，先确认相册授权。")
            return
        }

        let sessions = SessionBuilder.build(from: analyzed)
        let sizes = sessions.map(\.count).sorted()
        let median = sizes.isEmpty ? 0 : sizes[sizes.count / 2]
        log("会话：\(sessions.count) 个（中位 \(median) 张，最大 \(sizes.last ?? 0) 张）")

        let groupStarted = Date()
        let groups = Grouping.groups(assets: analyzed, prints: prints)
        log("分组：\(groups.count) 组 ≥2 张（耗时 \(seconds(since: groupStarted))）")

        if groups.isEmpty {
            log("")
            log("没有发现相似组。这在样本小的时候很正常——继续加大样本量再试。")
            return
        }

        let distribution = Dictionary(grouping: groups, by: { min($0.size, 5) })
            .sorted { $0.key < $1.key }
            .map { "\($0.key == 5 ? "5+" : "\($0.key)")张×\($0.value.count)" }
            .joined(separator: "  ")
        log("分布：\(distribution)")
        log("")

        let byID = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })

        for (offset, group) in groups.prefix(topGroups).enumerated() {
            log("── 第 \(offset + 1) 组 ── \(group.size) 张 · 凝聚度 \(String(format: "%.3f", group.cohesion)) · 跨度 \(duration(group.timeSpan)) · \(linkLabel(group.links))")

            var metrics: [AssetMetrics] = []
            var sharpnessByID: [String: Float] = [:]
            for assetID in group.assetIDs {
                guard let asset = byID[assetID] else { continue }
                guard let image = await Thumbnailer.image(for: assetID) else { continue }
                let sharpness = ImageQuality.sharpness(of: image)
                let face = ImageQuality.faceQuality(of: image)
                sharpnessByID[assetID] = sharpness
                metrics.append(
                    AssetMetrics(
                        assetID: assetID,
                        sharpness: sharpness,
                        faceQuality: face.score,
                        pixelCount: asset.pixelCount
                    )
                )
            }

            for (rank, keeper) in KeeperRanker.rank(metrics).enumerated() {
                let asset = byID[keeper.assetID]
                let name = asset?.originalFilename ?? String(keeper.assetID.prefix(12))
                let marker = rank == 0 ? "▶ 留" : "   "
                let sharpness = sharpnessByID[keeper.assetID].map { String(format: "%.0f", $0) } ?? "-"
                let dims = asset.map { "\($0.pixelWidth)×\($0.pixelHeight)" } ?? "-"
                let burst = (asset?.burstID != nil) ? " ·连拍" : ""
                log(
                    "  \(marker) \(name.padding(toLength: max(name.count, 18), withPad: " ", startingAt: 0))"
                        + " 分 \(String(format: "%.2f", keeper.score))"
                        + " · \(keeper.reason)"
                        + " · 清晰度 \(sharpness) · \(dims)\(burst)"
                )
            }
            log("")
        }
    }

    // MARK: - Steps

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
                        guard let image = await Thumbnailer.image(for: asset.id) else { return nil }
                        guard let vector = try? FeaturePrintService.vector(for: image) else { return nil }
                        return (asset.id, vector)
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
            progress = "特征 \(result.count)/\(assets.count)"
        }
        return result
    }

    // MARK: - Formatting

    private func log(_ line: String) {
        report.append(line)
    }

    private func seconds(since start: Date) -> String {
        String(format: "%.1fs", Date().timeIntervalSince(start))
    }

    private func duration(_ interval: TimeInterval) -> String {
        if interval < 60 { return String(format: "%.0fs", interval) }
        if interval < 3600 { return String(format: "%.0fmin", interval / 60) }
        return String(format: "%.1fh", interval / 3600)
    }

    private func linkLabel(_ links: Set<Grouping.Link>) -> String {
        var parts: [String] = []
        if links.contains(.burst) { parts.append("连拍") }
        if links.contains(.visual) { parts.append("视觉") }
        if links.contains(.crossSession) { parts.append("跨会话") }
        return parts.isEmpty ? "—" : parts.joined(separator: "+")
    }
}
