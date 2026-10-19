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

    func testThresholdsByGap() {
        XCTAssertEqual(ThresholdPolicy.default.minSimilarity(forGap: 1), 0.84, accuracy: 1e-6)
        XCTAssertEqual(ThresholdPolicy.default.minSimilarity(forGap: 30), 0.90, accuracy: 1e-6)
        XCTAssertEqual(ThresholdPolicy.default.minSimilarity(forGap: 3600), 0.92, accuracy: 1e-6)
    }

    /// 三档：≤5 秒 / ≤1 分钟 / ≤5 分钟。多一个数就多一处说不清的行为。
    func testThreeSteps() {
        XCTAssertEqual(ThresholdPolicy.default.steps.count, 3)
        XCTAssertEqual(ThresholdPolicy.screenshot.steps.count, 2)
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
        // 夹角 24° → 相似度 ≈ 0.914，在 0.84 和 0.92 之间
        let similar = ["a": vector(degrees: 0), "b": vector(degrees: 24)]
        let closeAssets = [asset("a", offset: 0), asset("b", offset: 1)]
        let farAssets = [asset("a", offset: 0), asset("b", offset: 120)]

        XCTAssertEqual(Grouping.groups(assets: closeAssets, prints: similar).count, 1)
        XCTAssertEqual(Grouping.groups(assets: farAssets, prints: similar).count, 0)
    }

    /// 不同会话之间不再合并：「改天重回同一地点」不是去重该干的事，
    /// 而它恰好是误合的最大来源。哪怕两张像到 0.99，隔了 1 小时也不进同一组。
    func testDifferentSessionsNeverMerge() {
        let assets = [asset("a", offset: 0), asset("b", offset: 3600)]
        let prints = ["a": vector(degrees: 0), "b": vector(degrees: 2)]
        XCTAssertEqual(Grouping.groups(assets: assets, prints: prints).count, 0)
    }

    /// 链式合并必须从原理上不可能：v0~v1、v1~v2、v2~v3 都过线，但 v0 与 v2、v3 差很远。
    /// 组要求「组内任意两张都过线」，所以链条断成 {v0,v1} 和 {v2,v3}。
    func testChainsCannotFormOneGroup() {
        let policy = ThresholdPolicy(steps: [.init(maxGap: 300, minSimilarity: 0.80)])
        let assets = (0..<4).map { asset("v\($0)", offset: Double($0)) }
        let prints = [
            "v0": vector(degrees: 0),
            "v1": vector(degrees: 20),
            "v2": vector(degrees: 40),
            "v3": vector(degrees: 60),
        ]
        let groups = Grouping.groups(assets: assets, prints: prints, policy: policy)

        XCTAssertEqual(groups.count, 2, "一条链必须断开，不能变成 1 组")
        XCTAssertEqual(groups.map { $0.assetIDs.sorted() }.sorted { $0[0] < $1[0] },
                       [["v0", "v1"], ["v2", "v3"]])
        for group in groups {
            XCTAssertGreaterThanOrEqual(group.cohesion, 0.80 - 1e-4)
        }
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

}
