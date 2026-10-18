import XCTest
@testable import GrazeCore

final class SessionTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func asset(_ id: String, offset: TimeInterval, burst: String? = nil) -> GrazeAsset {
        GrazeAsset(
            id: id,
            pixelWidth: 100,
            pixelHeight: 100,
            creationDate: base.addingTimeInterval(offset),
            burstID: burst,
            isScreenshot: false,
            isHidden: false,
            originalFilename: id,
            modificationDate: nil
        )
    }

    func testSplitsOnLargeGap() {
        let assets = [
            asset("a", offset: 0),
            asset("b", offset: 1),
            asset("c", offset: 3),
            asset("d", offset: 400),
            asset("e", offset: 402),
        ]
        let sessions = SessionBuilder.build(from: assets, maxGap: 90)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].assets.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(sessions[1].assets.map(\.id), ["d", "e"])
    }

    func testSortsUnorderedInput() {
        let assets = [asset("late", offset: 20), asset("early", offset: 0)]
        let sessions = SessionBuilder.build(from: assets)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].assets.map(\.id), ["early", "late"])
    }

    /// 没有拍摄时间的资产不能互相粘在一起：时间提供不了任何约束。
    func testUndatedAssetsStayIsolated() {
        let undated = (0..<3).map { index in
            GrazeAsset(
                id: "u\(index)",
                pixelWidth: 10,
                pixelHeight: 10,
                creationDate: nil,
                burstID: nil,
                isScreenshot: false,
                isHidden: false,
                originalFilename: nil,
                modificationDate: nil
            )
        }
        let sessions = SessionBuilder.build(from: undated)
        XCTAssertEqual(sessions.count, 3)
    }

    func testTimeSpan() {
        let session = PhotoSession(assets: [asset("a", offset: 0), asset("b", offset: 30)])
        XCTAssertEqual(session.timeSpan, 30, accuracy: 0.001)
    }
}

final class ThresholdPolicyTests: XCTestCase {
    func testThresholdGrowsWithGap() {
        let policy = ThresholdPolicy.default
        let gaps: [TimeInterval] = [0, 1, 2, 15, 30, 120, 300, 1800, 7200, 100_000]
        let thresholds = gaps.map { policy.minSimilarity(forGap: $0) }
        for (previous, next) in zip(thresholds, thresholds.dropFirst()) {
            XCTAssertLessThanOrEqual(previous, next, "阈值必须随间隔单调不减")
        }
    }

    func testShortGapIsPermissive() {
        XCTAssertEqual(ThresholdPolicy.default.minSimilarity(forGap: 1), 0.65, accuracy: 1e-6)
        XCTAssertEqual(ThresholdPolicy.default.minSimilarity(forGap: 3600), 0.85, accuracy: 1e-6)
    }
}

final class GroupingTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func asset(_ id: String, offset: TimeInterval, burst: String? = nil) -> GrazeAsset {
        GrazeAsset(
            id: id,
            pixelWidth: 100,
            pixelHeight: 100,
            creationDate: base.addingTimeInterval(offset),
            burstID: burst,
            isScreenshot: false,
            isHidden: false,
            originalFilename: id,
            modificationDate: nil
        )
    }

    /// 单位向量，夹角 `degrees`。
    private func vector(degrees: Double) -> [Float] {
        [Float(cos(degrees * .pi / 180)), Float(sin(degrees * .pi / 180))]
    }

    func testSameBurstIsGroupedRegardlessOfVisualDistance() {
        let assets = [
            asset("a", offset: 0, burst: "B1"),
            asset("b", offset: 1, burst: "B1"),
        ]
        // 完全正交：视觉上毫不相干
        let prints = ["a": vector(degrees: 0), "b": vector(degrees: 90)]
        let groups = Grouping.groups(assets: assets, prints: prints)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].assetIDs.sorted(), ["a", "b"])
        XCTAssertTrue(groups[0].links.contains(.burst))
    }

    func testSameSimilarityButDifferentGapGivesDifferentVerdict() {
        // 夹角 44° → 相似度 ≈ 0.72
        let similar = ["a": vector(degrees: 0), "b": vector(degrees: 44)]
        let closeAssets = [asset("a", offset: 0), asset("b", offset: 1)]
        let farAssets = [asset("a", offset: 0), asset("b", offset: 200)]

        XCTAssertEqual(Grouping.groups(assets: closeAssets, prints: similar).count, 1)
        XCTAssertEqual(Grouping.groups(assets: farAssets, prints: similar).count, 0)
    }

    func testCrossSessionMergeNeedsStricterSimilarity() {
        // 相隔 1 小时（不同会话），相似度 0.95
        let assets = [asset("a", offset: 0), asset("b", offset: 3600)]
        let prints = ["a": vector(degrees: 0), "b": vector(degrees: 18)]
        let groups = Grouping.groups(assets: assets, prints: prints)
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].links.contains(.crossSession))
    }

    /// 单链接链式合并：A~B~C~D 依次相邻都像，但 A 与 D 差很远。
    /// 组代表图 + 成员下限应该把最远的那张摘出去。
    func testMemberFloorStopsChaining() {
        let policy = ThresholdPolicy(
            steps: [.init(maxGap: 7200, minSimilarity: 0.70)],
            crossSessionMinSimilarity: 0.95,
            memberFloor: 0.80
        )
        let assets = (0..<4).map { asset("v\($0)", offset: Double($0)) }
        let prints = [
            "v0": vector(degrees: 0),
            "v1": vector(degrees: 20),
            "v2": vector(degrees: 40),
            "v3": vector(degrees: 60),
        ]
        let groups = Grouping.groups(assets: assets, prints: prints, policy: policy)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].assetIDs.sorted(), ["v0", "v1", "v2"])
    }

    func testCohesionIsMinPairwiseSimilarity() {
        let assets = [asset("a", offset: 0), asset("b", offset: 1)]
        let prints = ["a": vector(degrees: 0), "b": vector(degrees: 30)]
        let groups = Grouping.groups(assets: assets, prints: prints)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].cohesion, Float(cos(30.0 * .pi / 180)), accuracy: 1e-4)
    }

    func testSkipsAssetsWithoutFeaturePrints() {
        let assets = [asset("a", offset: 0), asset("b", offset: 1), asset("c", offset: 2)]
        let prints = ["a": vector(degrees: 0), "b": vector(degrees: 5)]
        let groups = Grouping.groups(assets: assets, prints: prints)
        XCTAssertEqual(groups.count, 1)
        XCTAssertFalse(groups[0].assetIDs.contains("c"))
    }

    // MARK: - 截图与照片分区

    private func screenshot(_ id: String, offset: TimeInterval) -> GrazeAsset {
        GrazeAsset(
            id: id,
            pixelWidth: 1179,
            pixelHeight: 2556,
            creationDate: base.addingTimeInterval(offset),
            burstID: nil,
            isScreenshot: true,
            isHidden: false,
            originalFilename: id,
            modificationDate: nil
        )
    }

    /// 照片和截图必须各自聚类。哪怕向量完全相同，也不能揉进一个组——
    /// 照片那套阈值用在截图上会全军误报。
    func testScreenshotsClusterSeparatelyFromPhotos() {
        let assets = [
            asset("p1", offset: 0),
            asset("p2", offset: 1),
            screenshot("s1", offset: 0),
            screenshot("s2", offset: 1),
        ]
        let prints = [
            "p1": vector(degrees: 0), "p2": vector(degrees: 2),
            "s1": vector(degrees: 0), "s2": vector(degrees: 2),
        ]
        let groups = Grouping.groups(assets: assets, prints: prints)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.filter { $0.kind == .photo }.first?.assetIDs.sorted(), ["p1", "p2"])
        XCTAssertEqual(groups.filter { $0.kind == .screenshot }.first?.assetIDs.sorted(), ["s1", "s2"])
    }

    /// 同一对相似度（≈0.963）相隔 1 小时：照片会被合并（跨会话阈值 0.88），
    /// 截图不应该（跨会话阈值 0.98）。这是真实图库里出现过的读数。
    func testSameSimilarityMergesPhotosButNotScreenshots() {
        let prints = ["a": vector(degrees: 0), "b": vector(degrees: 15.6)]

        let photos = [asset("a", offset: 0), asset("b", offset: 3600)]
        XCTAssertEqual(Grouping.groups(assets: photos, prints: prints).count, 1)

        let shots = [screenshot("a", offset: 0), screenshot("b", offset: 3600)]
        XCTAssertEqual(Grouping.groups(assets: shots, prints: prints).count, 0)
    }
}
