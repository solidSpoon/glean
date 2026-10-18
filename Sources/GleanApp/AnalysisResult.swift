import Foundation
import GleanCore

struct AnalyzedAsset: Identifiable {
    let id: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let isScreenshot: Bool
    let hasBurst: Bool
    /// 拉普拉斯方差（曝光归一化后）。数值本身没有绝对意义，只在组内横向比较。
    let sharpness: Float
    let faceQuality: Float?
    /// 与"建议保留"那张的相似度。自己就是保留张时为 1。
    let similarityToKeeper: Float?
    let score: Float
    let reason: String

    var fileExtension: String {
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "—" : ext.uppercased()
    }

    var pixelCount: Int { pixelWidth * pixelHeight }
}

struct AnalyzedGroup: Identifiable {
    let id: Int
    let kind: Grouping.Kind
    let cohesion: Float
    let timeSpan: TimeInterval
    let links: Set<Grouping.Link>
    /// false 表示只做了分组、还没算清晰度/人脸/评分（软加载）。
    let isScored: Bool
    /// 未评分时是分组顺序；评分后第一个是"建议留"。
    let assets: [AnalyzedAsset]
}

/// 全屏预览的状态。`index` 是组内下标，用于左右键翻看。
struct PreviewState: Identifiable {
    let group: AnalyzedGroup
    var index: Int

    var id: Int { group.id }

    var asset: AnalyzedAsset? {
        guard group.assets.indices.contains(index) else { return nil }
        return group.assets[index]
    }
}
