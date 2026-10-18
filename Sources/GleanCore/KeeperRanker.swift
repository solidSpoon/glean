import Foundation

public struct AssetMetrics: Sendable {
    public let assetID: String
    public let sharpness: Float
    /// nil = 没检测到人脸。
    public let faceQuality: Float?
    public let pixelCount: Int

    public init(assetID: String, sharpness: Float, faceQuality: Float?, pixelCount: Int) {
        self.assetID = assetID
        self.sharpness = sharpness
        self.faceQuality = faceQuality
        self.pixelCount = pixelCount
    }
}

public struct Keeper: Sendable {
    public let assetID: String
    /// 组内相对分，0–1。注意：**只有组内横向比较有意义**，跨组不可比。
    public let score: Float
    public let reason: String
}

/// 组内选优。
///
/// 关键设计：所有信号都只在**组内**做相对比较（除以组内最高值），因此不需要任何
/// 绝对阈值校准 —— "这张比那张清晰 30%"是稳定的，"清晰度 182"不是。
///
/// 注意别用 min-max：组里常常只有 2 张，min-max 会把 1% 的差异放大成 100%，
/// 人脸质量这类信号就完全失去作用了。相对最高值不会捏造差距。
public enum KeeperRanker {
    public static func rank(_ metrics: [AssetMetrics]) -> [Keeper] {
        guard !metrics.isEmpty else { return [] }
        guard metrics.count > 1 else {
            return [Keeper(assetID: metrics[0].assetID, score: 1, reason: "组内唯一")]
        }

        let sharpness = relative(metrics.map { log1p(max($0.sharpness, 0)) })
        let resolution = relative(metrics.map { log(Float(max($0.pixelCount, 1))) })

        let hasFaces = metrics.contains { $0.faceQuality != nil }
        let faces = hasFaces ? relative(metrics.map { $0.faceQuality ?? 0 }) : nil

        // 有人的照片，清晰度仍是最重要的，但人脸质量要占相当大的权重：
        // 一张糊了 20% 但眼睛睁开的照片，比清晰但闭眼的更值得留。
        let weights: (sharpness: Float, faces: Float, resolution: Float) =
            hasFaces ? (0.55, 0.30, 0.15) : (0.70, 0, 0.30)

        var scored: [Keeper] = []
        for (index, metric) in metrics.enumerated() {
            let face = faces?[index] ?? 0
            let score = weights.sharpness * sharpness[index]
                + weights.faces * face
                + weights.resolution * resolution[index]

            let reason: String
            if hasFaces, weights.faces * face >= weights.sharpness * sharpness[index] {
                reason = "人脸质量最好"
            } else if sharpness[index] >= 0.999 {
                reason = "组内最清晰"
            } else if resolution[index] >= 0.999 {
                reason = "分辨率最高"
            } else {
                reason = "次选"
            }
            scored.append(Keeper(assetID: metric.assetID, score: score, reason: reason))
        }

        return scored.sorted { $0.score > $1.score }
    }

    private static func relative(_ values: [Float]) -> [Float] {
        guard let high = values.max(), high > 0 else {
            return values.map { _ in 0 }
        }
        return values.map { max(0, $0) / high }
    }
}
