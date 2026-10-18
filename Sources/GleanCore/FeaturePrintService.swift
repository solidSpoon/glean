import CoreGraphics
import Foundation
import Vision

public enum FeaturePrintService {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// 用 Vision 的 FeaturePrint 提特征。
    ///
    /// 这是整个方案的核心：苹果自带、跑在 ANE 上、零依赖，对「重新压缩 /
    /// 轻微裁剪 / 调色 / 缩放 / 同一场景重拍」的鲁棒性远好于 pHash。
    /// 输出维度目前是 768。
    ///
    /// 注：macOS 15 起 Vision 有新的 async API
    /// (`GenerateImageFeaturePrintRequest`)，等接口稳定了再迁；这里先用
    /// 老的 VN* 接口，跨版本行为最确定。
    public static func vector(for image: CGImage) throws -> [Float] {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure(description: "Vision 请求失败: \(error.localizedDescription)")
        }

        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw Failure(description: "没有拿到特征输出")
        }
        guard observation.elementType == .float else {
            throw Failure(description: "未预期的元素类型: \(observation.elementType.rawValue)")
        }

        let count = observation.elementCount
        var values = [Float](repeating: 0, count: count)
        let byteCount = count * MemoryLayout<Float>.size
        _ = values.withUnsafeMutableBytes { buffer in
            observation.data.copyBytes(to: buffer, count: min(byteCount, observation.data.count))
        }
        return values
    }
}
