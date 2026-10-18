import Foundation
import Photos

/// 用自建相册当"标记"。
///
/// PhotoKit 不暴露 Photos 的"关键词"（⌘K 那个），但支持往用户相册里加照片。
/// 相册就是一组引用：不复制文件、不移动原图，而且**状态就存在系统里**——
/// 用户在 Photos.app 里把照片移出相册，我们下次读到的就是真实结果，不会有本地
/// 状态和现实不一致的问题。
///
/// 用户在 Photos.app 里打开这个相册、全选、删除，就是原生删除（进"最近删除"，
/// 30 天内可恢复）。
public enum DeletionAlbum {
    public static let title = "graze 待删除"

    public static func fetch() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        return PHAssetCollection
            .fetchAssetCollections(with: .album, subtype: .albumRegular, options: options)
            .firstObject
    }

    @discardableResult
    public static func findOrCreate() async throws -> PHAssetCollection? {
        if let existing = fetch() { return existing }

        var identifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            identifier = request.placeholderForCreatedAssetCollection.localIdentifier
        }

        if let identifier {
            let fetched = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [identifier],
                options: nil
            )
            if let collection = fetched.firstObject { return collection }
        }
        // 有些情况下 placeholder 的 identifier 拿不到，回退再查一次
        return fetch()
    }

    /// 当前相册里所有照片的标识。相册不存在就返回空集。
    public static func markedIdentifiers() -> Set<String> {
        guard let album = fetch() else { return [] }
        var ids = Set<String>()
        PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
            ids.insert(asset.localIdentifier)
        }
        return ids
    }

    public static func setMarked(_ identifiers: [String], marked: Bool) async throws {
        guard !identifiers.isEmpty else { return }
        guard let album = try await findOrCreate() else { return }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: album) else { return }
            if marked {
                request.addAssets(assets)
            } else {
                request.removeAssets(assets)
            }
        }
    }
}
