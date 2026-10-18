import Accelerate
import Foundation

/// 并查集。相似分组不用真的做 K-Means：拿阈值判断"这两个够像"，然后把
/// 够像的连成连通分量，就是分组了，代价 O(n²) 但常数极小。
public struct UnionFind {
    private var parent: [Int]
    private var size: [Int]

    public init(count: Int) {
        parent = Array(0..<count)
        size = Array(repeating: 1, count: count)
    }

    public mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        // 路径压缩
        var cur = x
        while parent[cur] != root {
            let next = parent[cur]
            parent[cur] = root
            cur = next
        }
        return root
    }

    public mutating func union(_ a: Int, _ b: Int) {
        var ra = find(a), rb = find(b)
        guard ra != rb else { return }
        if size[ra] < size[rb] { swap(&ra, &rb) }
        parent[rb] = ra
        size[ra] += size[rb]
    }

    /// 返回所有大小 >= 2 的连通分量，每组成员的原始下标。
    public mutating func groups(minimumSize: Int = 2) -> [[Int]] {
        var buckets: [Int: [Int]] = [:]
        for i in 0..<parent.count {
            buckets[find(i), default: []].append(i)
        }
        return buckets.values
            .filter { $0.count >= minimumSize }
            .sorted { $0.count > $1.count }
    }
}

public enum Similarity {
    /// 归一化成单位向量。零向量原样返回（后续会被跳过）。
    public static func normalized(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        guard norm > 0 else { return vector }
        let scale = 1 / norm.squareRoot()
        var out = [Float](repeating: 0, count: vector.count)
        var s = scale
        vDSP_vsmul(vector, 1, &s, &out, 1, vDSP_Length(vector.count))
        return out
    }

    /// 两个已归一化向量的余弦相似度（即点积）。
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot
    }

    /// 全量两两比较 + 连通分量分组。
    ///
    /// 个人图库（十万张以内）这个 O(n²) 暴力解法完全够用：十万张约 50 亿次
    /// Float 点积，Accelerate 下是几分钟级别，而且只需要在增量时算新图对旧图。
    /// 真到百万级再换 IVF / HNSW。
    public static func cluster(
        _ prints: [FeaturePrint],
        threshold: Float,
        minimumGroupSize: Int = 2
    ) -> [[Int]] {
        let vectors = prints.map { normalized($0.values) }
        var uf = UnionFind(count: vectors.count)

        for i in 0..<vectors.count {
            for j in (i + 1)..<vectors.count {
                if cosine(vectors[i], vectors[j]) >= threshold {
                    uf.union(i, j)
                }
            }
        }
        return uf.groups(minimumSize: minimumGroupSize)
    }
}
