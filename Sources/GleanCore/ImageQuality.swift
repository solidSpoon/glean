import Accelerate
import CoreGraphics
import Foundation
import Vision

/// 从像素里能直接拿到的质量信号。
public enum ImageQuality {
    /// 拉普拉斯响应的方差，除以平均亮度的平方做曝光归一化。
    ///
    /// 这是"糊没糊"最便宜也最有效的判据，而且恰好是连拍里最常见的失败原因（手抖、
    /// 主体移动）。数值本身没有绝对意义，只在同一组内横向比较。
    public static func sharpness(of image: CGImage, sampleSize: Int = 512) -> Float {
        let width = max(32, min(sampleSize, image.width))
        let height = max(32, min(sampleSize, image.height))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let base = context.data else { return 0 }
        let buffer = base.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        let rowBytes = context.bytesPerRow

        var sum: Double = 0
        var sumSquares: Double = 0
        var intensitySum: Double = 0
        var count: Double = 0

        for y in 1..<(height - 1) {
            let row = y * rowBytes
            for x in 1..<(width - 1) {
                let center = Double(buffer[row + x])
                let laplacian = 4 * center
                    - Double(buffer[row - rowBytes + x])
                    - Double(buffer[row + rowBytes + x])
                    - Double(buffer[row + x - 1])
                    - Double(buffer[row + x + 1])
                sum += laplacian
                sumSquares += laplacian * laplacian
                intensitySum += center
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        let mean = sum / count
        let variance = max(0, sumSquares / count - mean * mean)
        let meanIntensity = intensitySum / count
        // 拉普拉斯响应与对比度成正比，对比度低的图会"天然不清晰"，所以要归一化。
        return Float(variance / (meanIntensity * meanIntensity + 1))
    }

    /// 人脸质量：睁眼、清晰、朝向。人物照"哪张表情最好"几乎全靠它。
    public static func faceQuality(of image: CGImage) -> (score: Float?, faceCount: Int) {
        let request = VNDetectFaceCaptureQualityRequest()
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return (nil, 0)
        }
        let qualities = (request.results ?? []).compactMap { $0.faceCaptureQuality }
        return (qualities.max(), qualities.count)
    }
}
