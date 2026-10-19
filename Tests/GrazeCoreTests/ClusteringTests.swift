import XCTest
@testable import GrazeCore

final class ClusteringTests: XCTestCase {

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
