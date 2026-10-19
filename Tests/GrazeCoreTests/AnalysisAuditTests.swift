import XCTest
@testable import GrazeCore

final class AnalysisAuditTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func asset(_ id: String, offset: TimeInterval, dated: Bool = true) -> GrazeAsset {
        GrazeAsset(
            id: id,
            pixelWidth: 100,
            pixelHeight: 100,
            creationDate: dated ? base.addingTimeInterval(offset) : nil,
            burstID: nil,
            isScreenshot: false,
            isHidden: false,
            originalFilename: "\(id).jpg",
            modificationDate: dated ? base.addingTimeInterval(offset) : nil
        )
    }

    /// 同一场拍摄里的三张（0s / 10s / 120s），向量彼此都很像。
    private func fixture() -> (assets: [GrazeAsset], prints: [String: [Float]], groups: [Grouping.Group]) {
        let assets = [asset("a", offset: 0), asset("b", offset: 10), asset("c", offset: 120)]
        let prints: [String: [Float]] = [
            "a": [1, 0],
            "b": [1, 0.05],
            "c": [1, 0.1],
        ]
        return (assets, prints, Grouping.groups(assets: assets, prints: prints))
    }

    func testReportsMembersPairsAndThresholds() throws {
        let fixture = fixture()
        XCTAssertEqual(fixture.groups.count, 1, "fixture 本身就该合成一组")

        let report = AnalysisAudit.make(
            assets: fixture.assets,
            prints: fixture.prints,
            groups: fixture.groups
        )

        XCTAssertEqual(report.sample, 3)
        XCTAssertEqual(report.groupCount, 1)
        XCTAssertEqual(report.thresholds.photoSteps.count, 3)

        let group = try XCTUnwrap(report.groups.first)
        XCTAssertEqual(group.size, 3)
        XCTAssertEqual(group.pairs.count, 3, "三个成员应有 C(3,2)=3 对")
        XCTAssertEqual(Set(group.members.map(\.session)).count, 1, "组只该出现在单个会话内")

        let ab = try XCTUnwrap(group.pairs.first { $0.a == "a.jpg" && $0.b == "b.jpg" })
        XCTAssertEqual(ab.secondsApart, 10, accuracy: 0.001)
        XCTAssertEqual(ab.threshold, 0.90, accuracy: 0.0001, "10 秒走的是 ≤1 分钟那一档")
        XCTAssertTrue(ab.pass)
        XCTAssertFalse(ab.burstExempt)

        XCTAssertTrue(group.pairs.allSatisfy(\.pass), "进组的前提是每一对都过线")
        XCTAssertNotNil(group.weakestPair)
        XCTAssertNotNil(group.medianSimilarity)
    }

    /// 两档阈值在审计里也要能看出来：1 秒走 0.75，10 秒走 0.80。
    func testThresholdInAuditFollowsGap() throws {
        let assets = [asset("a", offset: 0), asset("b", offset: 1), asset("c", offset: 10)]
        let prints: [String: [Float]] = ["a": [1, 0], "b": [1, 0.01], "c": [1, 0.02]]
        let groups = Grouping.groups(assets: assets, prints: prints)
        XCTAssertEqual(groups.count, 1)

        let report = AnalysisAudit.make(assets: assets, prints: prints, groups: groups)
        let group = try XCTUnwrap(report.groups.first)

        let ab = try XCTUnwrap(group.pairs.first { $0.a == "a.jpg" && $0.b == "b.jpg" })
        XCTAssertEqual(ab.threshold, 0.84, accuracy: 0.0001, "1 秒属于「同一瞬间」那一档")

        let ac = try XCTUnwrap(group.pairs.first { $0.a == "a.jpg" && $0.b == "c.jpg" })
        XCTAssertEqual(ac.threshold, 0.90, accuracy: 0.0001, "10 秒属于「同一分钟」那一档")
    }

    /// JSON 必须能编码：漏掉这个，无限值之类的会让落盘静默失败。
    func testEncodesToJSON() throws {
        let fixture = fixture()
        let report = AnalysisAudit.make(
            assets: fixture.assets,
            prints: fixture.prints,
            groups: fixture.groups
        )
        let data = try JSONEncoder().encode(report)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\"weakestPair\""))
        XCTAssertTrue(text.contains("\"photoSteps\""))
        XCTAssertTrue(text.contains("\"sessionMaxGapSeconds\""))
    }

    /// 没有拍摄时间的资产也要能审计（secondsApart 用 -1 表示未知，不能是 inf）。
    func testUndatedAssetDoesNotBreakEncoding() throws {
        let assets = [asset("a", offset: 0), asset("b", offset: 10), asset("u", offset: 0, dated: false)]
        let prints: [String: [Float]] = ["a": [1, 0], "b": [1, 0.01], "u": [1, 0.02]]
        let groups = Grouping.groups(assets: assets, prints: prints)
        let report = AnalysisAudit.make(assets: assets, prints: prints, groups: groups)

        XCTAssertEqual(report.groups.count, 1, "没有时间的资产自己一个会话，不该入组")
        for pair in report.groups[0].pairs {
            XCTAssertGreaterThanOrEqual(pair.secondsApart, -1)
        }
        XCTAssertNoThrow(try JSONEncoder().encode(report))
    }
}
