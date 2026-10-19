import AppKit
import CoreGraphics
import Foundation
import Photos

public enum PhotoAccess {
    /// 用 readWrite 而不是 read：这个工具的最终动作是移出图库。
    /// 如果只想只读扫描，改成 .read 也能跑。
    public static func request() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    public static var current: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
}

public enum LibraryScanner {
    /// 抓取所有图片资产（含连拍、截图），跳过已隐藏的。
    /// `onProgress` 在枚举过程中回调 (已处理, 总数)，用于显示导入进度。
    public static func loadAssets(onProgress: ((Int, Int) -> Void)? = nil) -> [GrazeAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 关键：默认只返回连拍组的 key photo，其余 19 张完全不出现。
        // 不打开这个开关，“连拍”这个最该清理的场景在数据层面就消失了。
        options.includeAllBurstAssets = true
        let result = PHAsset.fetchAssets(with: .image, options: options)

        var out: [GrazeAsset] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { asset, index, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let original = resources.first { $0.type == .photo }?.originalFilename
            let subtypes = asset.mediaSubtypes
            out.append(
                GrazeAsset(
                    id: asset.localIdentifier,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    creationDate: asset.creationDate,
                    burstID: asset.burstIdentifier,
                    isScreenshot: subtypes.contains(.photoScreenshot),
                    isHidden: asset.isHidden,
                    originalFilename: original,
                    modificationDate: asset.modificationDate,
                    isFavorite: asset.isFavorite,
                    isLivePhoto: subtypes.contains(.photoLive),
                    isPanorama: subtypes.contains(.photoPanorama),
                    isHDR: subtypes.contains(.photoHDR),
                    isDepthEffect: subtypes.contains(.photoDepthEffect),
                    latitude: asset.location?.coordinate.latitude,
                    longitude: asset.location?.coordinate.longitude
                )
            )
            // 每 200 张报一次，别把 UI 线程刷满
            if index % 200 == 0 || index == result.count - 1 {
                onProgress?(index + 1, result.count)
            }
        }
        return out.filter { !$0.isHidden }
    }
}

public enum Thumbnailer {
    /// 取图结果。光有图/没图不够用：
    ///
    /// 「没图」有两种完全不同的原因——「这张只在 iCloud、本地没下载」和「取不出来」。
    /// 前者要告诉用户「去下载/确认网络」，后者是异常。混成一件事，界面就只能干转圈。
    public struct Outcome: Sendable {
        public let image: CGImage?
        /// PhotoKit 明确说「这张在 iCloud，本地没有」（`PHImageResultIsInCloudKey`）。
        public let isInCloud: Bool
    }

    /// 取本地可用的最大缩略图。
    ///
    /// 默认**不联网**：批量提特征时如果允许联网，「优化 Mac 储存空间」会把整个云端
    /// 图库悄悄拉下来，几十 GB、几十分钟，用户根本没同意这件事。
    /// 需要为「用户主动打开了这一张」下载时，把 `allowNetwork` 传 true。
    ///
    /// - Parameter targetSize: 512pt 对 Visual 特征足够，跟原图算出来的向量几乎一致。
    public static func image(
        for localIdentifier: String,
        targetSize: CGSize = CGSize(width: 512, height: 512),
        allowNetwork: Bool = false
    ) async -> CGImage? {
        await load(for: localIdentifier, targetSize: targetSize, allowNetwork: allowNetwork).image
    }

    /// 带结果分类的取图。`onProgress` 只在真从 iCloud 下载时会被调用，0…1。
    public static func load(
        for localIdentifier: String,
        targetSize: CGSize,
        allowNetwork: Bool = false,
        onProgress: ((Double) -> Void)? = nil
    ) async -> Outcome {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return Outcome(image: nil, isInCloud: false) }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowNetwork
        options.isSynchronous = false
        if allowNetwork, let onProgress {
            // PhotoKit 在后台队列回调进度，界面状态只能在主线程改。
            options.progressHandler = { progress, _, _, _ in
                DispatchQueue.main.async { onProgress(progress) }
            }
        }

        let box = ResumeBox()
        // 注意：macOS 上 requestImage 的回调给的是 NSImage（iOS 是 UIImage），
        // 拿 CGImage 得自己转。写错类型时编译器只会吐一句无用的
        // "failed to produce diagnostic"，别被它带偏。
        let result: (image: NSImage?, isInCloud: Bool) = await withCheckedContinuation {
            (continuation: CheckedContinuation<(NSImage?, Bool), Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // PhotoKit 可能回调多次（先给降质图、再给清晰图），也可能报错或取消。
                // 降质图一律丢掉；错误/取消必须立即 resume，否则 continuation 永远
                // 不会兑现，调用方的 task 就挂死了。
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let failed = (info?[PHImageErrorKey] as? Error) != nil
                let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                guard failed || cancelled || !degraded else { return }
                guard box.claim() else { return }
                let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool) ?? false
                continuation.resume(returning: (failed || cancelled ? nil : image, inCloud))
            }
        }

        guard let nsImage = result.image else {
            return Outcome(image: nil, isInCloud: result.isInCloud)
        }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        return Outcome(image: cgImage, isInCloud: result.isInCloud)
    }
}

/// 保证 continuation 只 resume 一次（PhotoKit 的回调不保证只来一次）。
private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return false }
        done = true
        return true
    }
}
