import XCTest
@testable import GrazeCore

final class FeatureCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("graze-featurecache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func asset(_ id: String, modifiedOffset: TimeInterval = 0, width: Int = 100) -> GrazeAsset {
        GrazeAsset(
            id: id,
            pixelWidth: width,
            pixelHeight: 100,
            creationDate: base,
            burstID: nil,
            isScreenshot: false,
            isHidden: false,
            originalFilename: id,
            modificationDate: base.addingTimeInterval(modifiedOffset)
        )
    }

    /// 用 Float16 能精确表示的数值，round-trip 之后才能逐位比较。
    private func vector(_ seed: Float) -> [Float] {
        (0..<8).map { seed + Float($0) / 2 }
    }

    func testRoundTripAfterReload() {
        let cache = FeatureCache(directory: directory)
        let a = asset("a"), b = asset("b")
        cache.store(["a": vector(1), "b": vector(2)], for: [a, b])
        cache.save()

        cache.reload()
        let (cached, pending) = cache.partition([a, b])
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(cached.keys.sorted(), ["a", "b"])
        XCTAssertEqual(cached["a"], vector(1))
        XCTAssertEqual(cached["b"], vector(2))
    }

    func testModifiedOrResizedAssetIsMiss() {
        let cache = FeatureCache(directory: directory)
        let original = asset("a")
        cache.store(["a": vector(1)], for: [original])
        cache.save()

        cache.reload()
        let (cached, pending) = cache.partition([
            asset("a", modifiedOffset: 60),
            asset("a", width: 200),
        ])
        XCTAssertTrue(cached.isEmpty)
        XCTAssertEqual(pending.count, 2)
    }

    /// Vision revision 变了，向量空间也就变了：整份缓存必须作废，而不是按 id 复用。
    func testForeignRevisionIsDiscarded() throws {
        let cache = FeatureCache(directory: directory)
        let a = asset("a")
        cache.store(["a": vector(1)], for: [a])
        cache.save()

        // 把文件头的 revision 改成一个不存在的值。
        var data = try Data(contentsOf: URL(fileURLWithPath: cache.filePath))
        let revisionOffset = 8 + 4
        data.replaceSubrange(revisionOffset..<(revisionOffset + 4), with: Data([99, 0, 0, 0]))
        try data.write(to: URL(fileURLWithPath: cache.filePath))

        cache.reload()
        let (cached, pending) = cache.partition([a])
        XCTAssertTrue(cached.isEmpty)
        XCTAssertEqual(pending.count, 1)
    }

    func testTruncatedFileIsIgnored() throws {
        let cache = FeatureCache(directory: directory)
        let a = asset("a")
        cache.store(["a": vector(1)], for: [a])
        cache.save()

        let data = try Data(contentsOf: URL(fileURLWithPath: cache.filePath))
        try data.prefix(data.count - 20).write(to: URL(fileURLWithPath: cache.filePath))

        cache.reload()
        // 不能崩，也不能把半条记录当成完整向量用。
        let (cached, pending) = cache.partition([a])
        XCTAssertTrue(cached.isEmpty)
        XCTAssertEqual(pending.count, 1)
    }

    func testRetainDropsDeletedAssets() {
        let cache = FeatureCache(directory: directory)
        let a = asset("a"), b = asset("b")
        cache.store(["a": vector(1), "b": vector(2)], for: [a, b])
        cache.retain(ids: ["a"])

        cache.reload()
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.partition([b]).pending.count, 1)
    }
}
