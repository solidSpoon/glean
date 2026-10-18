import Foundation
import GleanCore

struct AnalyzedAsset: Identifiable {
    let id: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let isScreenshot: Bool
    let hasBurst: Bool
    /// 拉普拉斯方差（曝光归一化后）。数值本身没有绝对意义，只在组内横向比较。
    let sharpness: Float
    let faceQuality: Float?
    let score: Float
    let reason: String
}

struct AnalyzedGroup: Identifiable {
    let id: Int
    let kind: Grouping.Kind
    let cohesion: Float
    let timeSpan: TimeInterval
    let links: Set<Grouping.Link>
    /// 已按建议排序，第一个是"建议留"的那张。
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
