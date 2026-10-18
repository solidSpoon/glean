import Foundation

/// 一条相册资产的轻量快照。
///
/// 只保留后续做「分组 / 选优」真正需要的字段，避免把 PHAsset 传进并发代码里
/// （PHAsset 不是 Sendable，跨 actor 传会炸）。
public struct GrazeAsset: Sendable, Identifiable, Hashable {
    /// PHAsset.localIdentifier —— 在同一个 Photos 库里长期稳定，适合当主键。
    public let id: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let creationDate: Date?
    /// 连拍组的标识。连拍整组天然就是一个「相似组」，不用算特征。
    public let burstID: String?
    public let isScreenshot: Bool
    public let isHidden: Bool
    public let originalFilename: String?
    /// 最近一次修改时间，增量扫描用。
    public let modificationDate: Date?
    public let isFavorite: Bool
    public let isLivePhoto: Bool
    public let isPanorama: Bool
    public let isHDR: Bool
    public let isDepthEffect: Bool
    public let latitude: Double?
    public let longitude: Double?

    public init(
        id: String,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date?,
        burstID: String?,
        isScreenshot: Bool,
        isHidden: Bool,
        originalFilename: String?,
        modificationDate: Date?,
        isFavorite: Bool = false,
        isLivePhoto: Bool = false,
        isPanorama: Bool = false,
        isHDR: Bool = false,
        isDepthEffect: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.burstID = burstID
        self.isScreenshot = isScreenshot
        self.isHidden = isHidden
        self.originalFilename = originalFilename
        self.modificationDate = modificationDate
        self.isFavorite = isFavorite
        self.isLivePhoto = isLivePhoto
        self.isPanorama = isPanorama
        self.isHDR = isHDR
        self.isDepthEffect = isDepthEffect
        self.latitude = latitude
        self.longitude = longitude
    }

    public var pixelCount: Int { pixelWidth * pixelHeight }
}

/// 一张图的特征向量。归一化后存，余弦相似度就退化成点积。
public struct FeaturePrint: Sendable {
    public let assetID: String
    public let values: [Float]

    public init(assetID: String, values: [Float]) {
        self.assetID = assetID
        self.values = values
    }
}
