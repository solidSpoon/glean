import CoreGraphics
import Foundation

/// 缩略图内存缓存。
///
/// 没有这一层，滑动预览网格时每个 cell 都会重新向 PhotoKit 请求图片，滚起来会卡死。
public final class ThumbnailCache: @unchecked Sendable {
    public static let shared = ThumbnailCache()

    private final class Box {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private let cache = NSCache<NSString, Box>()

    private init() {
        cache.countLimit = 600
        // 256pt 缩略图约 256KB/张，120MB 上限大约留得住 450 张
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    public func image(for localIdentifier: String, target: CGFloat = 256) async -> CGImage? {
        let key = "\(localIdentifier)#\(Int(target))" as NSString
        if let hit = cache.object(forKey: key) { return hit.image }

        guard let image = await Thumbnailer.image(
            for: localIdentifier,
            targetSize: CGSize(width: target, height: target)
        ) else { return nil }

        cache.setObject(Box(image), forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
