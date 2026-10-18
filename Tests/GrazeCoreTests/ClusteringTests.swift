import XCTest
@testable import GrazeCore

final class ClusteringTests: XCTestCase {
    func testUnionFindMergesTransitively() {
        var uf = UnionFind(count: 5)
        uf.union(0, 1)
        uf.union(1, 2)

        XCTAssertEqual(uf.find(0), uf.find(2), "0-1、1-2 相连，0 和 2 就该同根")
        XCTAssertNotEqual(uf.find(0), uf.find(3))

        var roots = Set<Int>()
        for index in 0..<5 {
            roots.insert(uf.find(index))
        }
        XCTAssertEqual(roots.count, 3, "应分成 {0,1,2} / {3} / {4}")
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
}
