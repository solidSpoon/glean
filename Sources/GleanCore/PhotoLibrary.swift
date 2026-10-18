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
    public static func loadAssets() -> [GleanAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // 关键：默认只返回连拍组的 key photo，其余 19 张完全不出现。
        // 不打开这个开关，“连拍”这个最该清理的场景在数据层面就消失了。
        options.includeAllBurstAssets = true
        let result = PHAsset.fetchAssets(with: .image, options: options)

        var out: [GleanAsset] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            let resources = PHAssetResource.assetResources(for: asset)
            let original = resources.first { $0.type == .photo }?.originalFilename
            out.append(
                GleanAsset(
                    id: asset.localIdentifier,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    creationDate: asset.creationDate,
                    burstID: asset.burstIdentifier,
                    isScreenshot: asset.mediaSubtypes.contains(.photoScreenshot),
                    isHidden: asset.isHidden,
                    originalFilename: original,
                    modificationDate: asset.modificationDate
                )
            )
        }
        return out.filter { !$0.isHidden }
    }
}

public enum Thumbnailer {
    /// 取本地可用的最大缩略图。关键点：
    /// - `isNetworkAccessAllowed = false` 保证不会因为「优化存储」把 iCloud 原图
    ///   全部下载下来
    /// - 512pt 对 Visual 特征来说足够，跟原图算出来的向量几乎一致
    public static func image(
        for localIdentifier: String,
        targetSize: CGSize = CGSize(width: 512, height: 512)
    ) async -> CGImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        let box = ResumeBox()
        // 注意：macOS 上 requestImage 的回调给的是 NSImage（iOS 是 UIImage），
        // 拿 CGImage 得自己转。写错类型时编译器只会吐一句无用的
        // "failed to produce diagnostic"，别被它带偏。
        let nsImage: NSImage? = await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                // 可能回调多次：先给降质图再给清晰图。只认最后一次。
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if isDegraded { return }
                if box.claim() { continuation.resume(returning: image) }
            }
        }

        guard let nsImage else { return nil }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)
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
