// 图标方案生成器。
// 用法：swift scripts/render-icon.swift
// 输出：build/icons/*.png 与 build/icons/contact-sheet.png
import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let dir = "build/icons"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func white(_ alpha: CGFloat) -> CGColor {
    CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
}

func fillGradient(_ c: CGContext, rect: CGRect, _ from: UInt32, _ to: UInt32) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let gradient = CGGradient(
        colorsSpace: space,
        colors: [rgb(from), rgb(to)] as CFArray,
        locations: [0, 1]
    ) else { return }
    c.saveGState()
    c.clip(to: rect)
    c.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )
    c.restoreGState()
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat, rotate: CGFloat = 0, around center: CGPoint? = nil) -> CGPath {
    var transform = CGAffineTransform.identity
    if rotate != 0, let center {
        transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotate)
            .translatedBy(x: -center.x, y: -center.y)
    }
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: &transform)
}

// MARK: - 底板

func plate(_ c: CGContext, _ from: UInt32, _ to: UInt32) {
    let inset: CGFloat = 88
    let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: 196, cornerHeight: 196, transform: nil)

    c.saveGState()
    c.addPath(path)
    c.clip()
    fillGradient(c, rect: rect, from, to)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if let gloss = CGGradient(
        colorsSpace: space,
        colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
        locations: [0, 1]
    ) {
        c.drawLinearGradient(
            gloss,
            start: CGPoint(x: 0, y: rect.maxY),
            end: CGPoint(x: 0, y: rect.midY),
            options: []
        )
    }
    c.restoreGState()

    c.addPath(path)
    c.setStrokeColor(white(0.13))
    c.setLineWidth(3)
    c.strokePath()
}

// MARK: - A 麦穗

func drawWheat(_ c: CGContext) {
    plate(c, 0x1F4D3A, 0x3A8A64)
    let gold = rgb(0xF6CE63)

    c.setStrokeColor(gold)
    c.setLineWidth(26)
    c.setLineCap(.round)
    c.move(to: CGPoint(x: 512, y: 250))
    c.addLine(to: CGPoint(x: 512, y: 676))
    c.strokePath()

    c.setFillColor(gold)
    for row in 0..<3 {
        let y = 318.0 + CGFloat(row) * 112
        for side in [CGFloat(-1), CGFloat(1)] {
            c.saveGState()
            c.translateBy(x: 512, y: y)
            c.rotate(by: side * 0.60)
            c.addEllipse(in: CGRect(x: -42, y: 22, width: 84, height: 138))
            c.fillPath()
            c.restoreGState()
        }
    }
    c.saveGState()
    c.translateBy(x: 512, y: 716)
    c.addEllipse(in: CGRect(x: -42, y: -16, width: 84, height: 140))
    c.fillPath()
    c.restoreGState()
}

// MARK: - B 叠放照片 + 勾

func drawStack(_ c: CGContext) {
    plate(c, 0x2F6BFF, 0x1839BE)
    let center = CGPoint(x: 512, y: 512)

    // 后面一张：往左上错开并描边，否则两张白卡会糊成一张
    let backRect = CGRect(x: 512 - 262, y: 512 - 112, width: 452, height: 340)
    let backPath = roundedRect(backRect, 36, rotate: -0.24, around: center)
    c.addPath(backPath)
    c.setFillColor(white(0.32))
    c.fillPath()
    c.addPath(backPath)
    c.setStrokeColor(white(0.45))
    c.setLineWidth(5)
    c.strokePath()

    // 前面一张
    let frontRect = CGRect(x: 512 - 208, y: 512 - 218, width: 466, height: 368)
    c.addPath(roundedRect(frontRect, 40, rotate: 0.07, around: center))
    c.setFillColor(white(0.97))
    c.fillPath()

    // 勾
    c.setStrokeColor(rgb(0x21C07A))
    c.setLineWidth(34)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 424, y: 512))
    c.addLine(to: CGPoint(x: 494, y: 442))
    c.addLine(to: CGPoint(x: 612, y: 578))
    c.strokePath()
}

// MARK: - C 三张里选一张

func drawSieve(_ c: CGContext) {
    plate(c, 0x2F3338, 0x101317)
    let side: CGFloat = 188
    let gap: CGFloat = 34
    let total = side * 3 + gap * 2
    let originX = (canvas - total) / 2
    let originY = (canvas - side) / 2

    for index in 0..<3 {
        let x = originX + CGFloat(index) * (side + gap)
        let rect = CGRect(x: x, y: originY, width: side, height: side)
        let selected = index == 1
        c.addPath(roundedRect(rect, 30))
        c.setFillColor(selected ? rgb(0xF6CE63) : white(0.20))
        c.fillPath()
        if !selected {
            c.addPath(roundedRect(rect, 30))
            c.setStrokeColor(white(0.22))
            c.setLineWidth(4)
            c.strokePath()
        }
    }

    // 选中那张上打个勾
    c.setStrokeColor(rgb(0x2A2E33))
    c.setLineWidth(22)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    let centerX = originX + (side + gap) + side / 2
    let midY = originY + side / 2
    c.move(to: CGPoint(x: centerX - 42, y: midY + 2))
    c.addLine(to: CGPoint(x: centerX - 8, y: midY - 36))
    c.addLine(to: CGPoint(x: centerX + 46, y: midY + 44))
    c.strokePath()
}

// MARK: - D 九宫格里抬起一格

func drawGrid(_ c: CGContext) {
    plate(c, 0x6B4CF0, 0x3820B8)
    let size: CGFloat = 116
    let gap: CGFloat = 44
    let total = size * 3 + gap * 2
    let originX = (canvas - total) / 2
    let originY = (canvas - total) / 2

    for row in 0..<3 {
        for col in 0..<3 {
            let raised = row == 1 && col == 1
            let scale: CGFloat = raised ? 1.22 : 1
            let side = size * scale
            let x = originX + CGFloat(col) * (size + gap) - (side - size) / 2
            let y = originY + CGFloat(row) * (size + gap) - (side - size) / 2
            let rect = CGRect(x: x, y: y, width: side, height: side)

            if raised {
                c.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
                c.setFillColor(rgb(0xFFD166))
                c.addPath(roundedRect(rect, 34))
                c.fillPath()
                c.setShadow(offset: .zero, blur: 0, color: nil)
            } else {
                c.setFillColor(white(0.32))
                c.addPath(roundedRect(rect, 34))
                c.fillPath()
            }
        }
    }
}

// MARK: - E 取景框 + 照片

func drawViewfinder(_ c: CGContext) {
    plate(c, 0xFF8A3D, 0xD6431F)
    let ink = white(0.96)

    c.setStrokeColor(ink)
    c.setLineWidth(26)
    c.setLineCap(.round)

    let left: CGFloat = 286, right: CGFloat = 738, bottom: CGFloat = 286, top: CGFloat = 738
    let arm: CGFloat = 132
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: left, y: top - arm), CGPoint(x: left, y: top), CGPoint(x: left + arm, y: top)),
        (CGPoint(x: right - arm, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: top - arm)),
        (CGPoint(x: left, y: bottom + arm), CGPoint(x: left, y: bottom), CGPoint(x: left + arm, y: bottom)),
        (CGPoint(x: right - arm, y: bottom), CGPoint(x: right, y: bottom), CGPoint(x: right, y: bottom + arm)),
    ]
    for (a, b, d) in corners {
        c.move(to: a)
        c.addLine(to: b)
        c.addLine(to: d)
    }
    c.strokePath()

    // 框里一张小照片 + 勾
    c.setFillColor(ink)
    c.addPath(roundedRect(CGRect(x: 512 - 128, y: 512 - 92, width: 256, height: 184), 24))
    c.fillPath()

    c.setStrokeColor(rgb(0xD6431F))
    c.setLineWidth(20)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 448, y: 512))
    c.addLine(to: CGPoint(x: 494, y: 464))
    c.addLine(to: CGPoint(x: 580, y: 556))
    c.strokePath()
}

// MARK: - F 三张照片扇形

func drawFan(_ c: CGContext) {
    plate(c, 0x2B3038, 0x14171C)
    let pivot = CGPoint(x: 512, y: 300)
    let angles: [CGFloat] = [-0.42, 0, 0.42]

    for (index, angle) in angles.enumerated() {
        let rect = CGRect(x: 512 - 200, y: 390, width: 400, height: 290)
        let path = roundedRect(rect, 34, rotate: angle, around: pivot)
        let alpha: CGFloat = index == 2 ? 0.97 : 0.30
        c.addPath(path)
        c.setFillColor(white(alpha))
        c.fillPath()
        if index != 2 {
            c.addPath(path)
            c.setStrokeColor(white(0.40))
            c.setLineWidth(5)
            c.strokePath()
        }
    }

    // 最前一张上的勾（跟着旋转）
    c.saveGState()
    c.translateBy(x: pivot.x, y: pivot.y)
    c.rotate(by: 0.42)
    c.translateBy(x: -pivot.x, y: -pivot.y)
    c.setStrokeColor(rgb(0x21C07A))
    c.setLineWidth(30)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 438, y: 560))
    c.addLine(to: CGPoint(x: 498, y: 500))
    c.addLine(to: CGPoint(x: 600, y: 616))
    c.strokePath()
    c.restoreGState()
}

// MARK: - 渲染

struct Candidate {
    let letter: String
    let name: String
    let draw: (CGContext) -> Void
}

let candidates: [Candidate] = [
    Candidate(letter: "A", name: "麦穗", draw: drawWheat),
    Candidate(letter: "B", name: "叠放照片", draw: drawStack),
    Candidate(letter: "C", name: "三选一", draw: drawSieve),
    Candidate(letter: "D", name: "九宫格", draw: drawGrid),
    Candidate(letter: "E", name: "取景框", draw: drawViewfinder),
    Candidate(letter: "F", name: "扇形照片", draw: drawFan),
]

var rendered: [(Candidate, CGImage)] = []
for candidate in candidates {
    let c = makeContext(Int(canvas), Int(canvas))
    candidate.draw(c)
    guard let image = c.makeImage() else { continue }
    rendered.append((candidate, image))

    let rep = NSBitmapImageRep(cgImage: image)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(candidate.letter).png"))
    }
}

// MARK: - 对比图

let cellWidth: CGFloat = 620
let cellHeight: CGFloat = 760
let cols = 3
let rows = 2
let sheetWidth = Int(cellWidth) * cols
let sheetHeight = Int(cellHeight) * rows

let sheet = makeContext(sheetWidth, sheetHeight)
sheet.setFillColor(rgb(0x111418))
sheet.fill(CGRect(x: 0, y: 0, width: CGFloat(sheetWidth), height: CGFloat(sheetHeight)))

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)

for (index, entry) in rendered.enumerated() {
    let col = index % cols
    let row = index / cols
    let x = CGFloat(col) * cellWidth
    let y = CGFloat(rows - 1 - row) * cellHeight

    let iconRect = CGRect(x: x + (cellWidth - 480) / 2, y: y + 150, width: 480, height: 480)
    sheet.draw(entry.1, in: iconRect)

    let label = "\(entry.0.letter)  \(entry.0.name)" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 40, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]
    let size = label.size(withAttributes: attributes)
    label.draw(at: CGPoint(x: x + (cellWidth - size.width) / 2, y: y + 70), withAttributes: attributes)
}

NSGraphicsContext.restoreGraphicsState()

if let sheetImage = sheet.makeImage() {
    let rep = NSBitmapImageRep(cgImage: sheetImage)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/contact-sheet.png"))
    }
}

print("rendered \(rendered.count) candidates → \(dir)")
