import XCTest
@testable import GleanCore

final class ClusteringTests: XCTestCase {
    func testUnionFindGroups() {
        var uf = UnionFind(count: 5)
        uf.union(0, 1)
        uf.union(1, 2)
        let groups = uf.groups()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].sorted(), [0, 1, 2])
    }

    func testNormalizeProducesUnitVector() {
        let n = Similarity.normalized([3, 4])
        XCTAssertEqual(n[0], 0.6, accuracy: 1e-6)
        XCTAssertEqual(n[1], 0.8, accuracy: 1e-6)
    }

    func testCosineOfIdenticalIsOne() {
        let a = Similarity.normalized([1, 2, 3, 4])
        XCTAssertEqual(Similarity.cosine(a, a), 1.0, accuracy: 1e-5)
    }

    func testClusterSeparatesOrthogonalVectors() {
        let prints = [
            FeaturePrint(assetID: "a", values: [1, 0, 0]),
            FeaturePrint(assetID: "b", values: [0.99, 0.01, 0]),
            FeaturePrint(assetID: "c", values: [0, 1, 0]),
            FeaturePrint(assetID: "d", values: [0, 0, 1]),
        ]
        let groups = Similarity.cluster(prints, threshold: 0.9)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].sorted(), [0, 1])
    }
}
