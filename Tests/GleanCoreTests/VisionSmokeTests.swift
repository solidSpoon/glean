import CoreGraphics
import XCTest
@testable import GleanCore

/// 离线标定：不碰相册，用合成图像量一下 FeaturePrint 在"同一张图被糊掉"这个最关键的
/// 场景上到底给多少分。这不是靠猜的，断言只锁定方向性（模糊越重分数越低），具体数值
/// 打印出来当参考基线。
final class VisionSmokeTests: XCTestCase {
    private let size = 512

    private let layoutA: [CGPoint] = [
        CGPoint(x: 140, y: 160),
        CGPoint(x: 300, y: 220),
        CGPoint(x: 230, y: 360),
    ]

    private let layoutB: [CGPoint] = [
        CGPoint(x: 90, y: 120),
        CGPoint(x: 380, y: 90),
        CGPoint(x: 400, y: 300),
    ]

    private func makeContext(_ width: Int, _ height: Int) -> CGContext {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
    }

    /// 模拟一张真实照片：渐变背景 + 几个主体 + 一块高光。
    /// 刻意不用棋盘格那类"纯纹理"——那是 FeaturePrint 的病态输入，量出来的数字没有参考价值。
    private func scene(circles: [CGPoint], reversedGradient: Bool = false) -> CGImage {
        let context = makeContext(size, size)
        let gray = CGColorSpaceCreateDeviceGray()
        let colors = [CGColor(gray: 0.18, alpha: 1), CGColor(gray: 0.82, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: gray, colors: colors, locations: [0, 1]) {
            let start = reversedGradient ? CGPoint(x: CGFloat(size), y: 0) : .zero
            let end = reversedGradient
                ? CGPoint(x: 0, y: CGFloat(size))
                : CGPoint(x: CGFloat(size), y: CGFloat(size))
            context.drawLinearGradient(gradient, start: start, end: end, options: [])
        }
        context.setFillColor(CGColor(gray: 0.06, alpha: 1))
        for center in circles {
            context.fillEllipse(
                in: CGRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140)
            )
        }
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: 120, height: 40))
        return context.makeImage()!
    }

    /// 先缩小再放大：抹掉高频，等价于"糊了"。
    private func blurred(_ image: CGImage, factor: Int) -> CGImage {
        let width = max(8, image.width / factor)
        let height = max(8, image.height / factor)
        let small = makeContext(width, height)
        small.interpolationQuality = .high
        small.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let downscaled = small.makeImage() else { return image }

        let restored = makeContext(image.width, image.height)
        restored.interpolationQuality = .high
        restored.draw(downscaled, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return restored.makeImage() ?? image
    }

    func testSharpnessDetectsBlur() {
        let sharp = scene(circles: layoutA)
        let blurry = blurred(sharp, factor: 8)

        let sharpValue = ImageQuality.sharpness(of: sharp)
        let blurryValue = ImageQuality.sharpness(of: blurry)

        XCTAssertGreaterThan(sharpValue, 0)
        XCTAssertGreaterThan(sharpValue, blurryValue * 3, "模糊图的拉普拉斯方差应明显更低")
    }

    func testSimilarityCalibration() throws {
        let sharp = scene(circles: layoutA)
        let mild = blurred(sharp, factor: 2)
        let medium = blurred(sharp, factor: 4)
        let heavy = blurred(sharp, factor: 8)
        let rearranged = scene(circles: layoutB)
        let different = scene(circles: layoutB, reversedGradient: true)

        let base = Similarity.normalized(try FeaturePrintService.vector(for: sharp))
        func similarity(_ image: CGImage) throws -> Float {
            Similarity.cosine(base, Similarity.normalized(try FeaturePrintService.vector(for: image)))
        }

        let measurements: [(String, Float)] = [
            ("同一张 · 轻微模糊 2x", try similarity(mild)),
            ("同一张 · 中度模糊 4x", try similarity(medium)),
            ("同一张 · 重度模糊 8x", try similarity(heavy)),
            ("同背景 · 主体移位", try similarity(rearranged)),
            ("不同场景", try similarity(different)),
        ]

        print("[calibration] 特征维度 \(base.count)")
        for (label, value) in measurements {
            print("[calibration] \(label.padding(toLength: 22, withPad: " ", startingAt: 0)) \(String(format: "%.3f", value))")
        }

        XCTAssertGreaterThan(measurements[0].1, measurements[2].1, "模糊越重，相似度应越低")
        // 不断言“重度模糊仍比无关场景更像”：这几张合成图都是“渐变背景+几个圆+一块高光”，
        // 语义上属于同一类东西，FeaturePrint 给出的 0.957 几乎等于“同背景主体移位”的 0.967。
        // 这说明用合成图根本测不了“不同场景能否分开”——必须用真实照片，也就是 audit 模式。
    }

    func testFeaturePrintThroughput() throws {
        let images = (0..<16).map { _ in scene(circles: layoutA) }
        let started = Date()
        for image in images {
            _ = try FeaturePrintService.vector(for: image)
        }
        let elapsed = Date().timeIntervalSince(started)
        let perImage = elapsed / Double(images.count) * 1000
        print(String(format: "[calibration] FeaturePrint 单张 %.1f ms，约 %.0f 张/秒", perImage, 1000 / perImage))
        XCTAssertLessThan(perImage, 500, "单张耗时异常")
    }
}
