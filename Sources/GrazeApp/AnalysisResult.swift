import Foundation
import GrazeCore

struct AnalyzedAsset: Identifiable {
    let id: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let modificationDate: Date?
    let isScreenshot: Bool
    let hasBurst: Bool
    let isFavorite: Bool
    let isLivePhoto: Bool
    let isPanorama: Bool
    let isHDR: Bool
    let isDepthEffect: Bool
    let latitude: Double?
    let longitude: Double?
    /// 与组内其他成员的最低 / 最高相似度。纯展示用，不参与任何取舍判断——
    /// 这个工具只负责把重复的找出来，挑哪张留给人。
    let similarityMin: Float?
    let similarityMax: Float?

    var fileExtension: String {
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "—" : ext.uppercased()
    }

    var pixelCount: Int { pixelWidth * pixelHeight }

    /// 属性线。"普通照片" 作为空集合的回退。
    var attributeLabels: [String] {
        var parts: [String] = []
        if isFavorite { parts.append("收藏") }
        if isScreenshot { parts.append("截图") }
        if hasBurst { parts.append("连拍") }
        if isLivePhoto { parts.append("实况") }
        if isPanorama { parts.append("全景") }
        if isHDR { parts.append("HDR") }
        if isDepthEffect { parts.append("景深") }
        return parts
    }
}

struct AnalyzedGroup: Identifiable {
    let id: Int
    let kind: Grouping.Kind
    let cohesion: Float
    let timeSpan: TimeInterval
    /// 组内最新拍摄时间，列表排序依据。
    let latestDate: Date?
    let links: Set<Grouping.Link>
    /// 组内成员，按拍摄时间正序。
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
