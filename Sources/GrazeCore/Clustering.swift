import Accelerate
import Foundation

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
    ///
    /// 不在这里做归一化：这个函数假定入参已经是单位向量，否则结果不是余弦而是
    /// 内积，数值会悄悄超出 [−1, 1]。
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot
    }
}
