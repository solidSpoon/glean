// 图标方案生成器（麦穗系列）。
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
        colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.15), CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
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

// MARK: - 麦穗基元

/// 一粒麦子：底端固定在锚点上，向上伸。
func drawGrain(
    _ c: CGContext,
    at anchor: CGPoint,
    angle: CGFloat,
    width: CGFloat,
    height: CGFloat,
    color: CGColor,
    outlined: Bool = false,
    lineWidth: CGFloat = 14
) {
    c.saveGState()
    c.translateBy(x: anchor.x, y: anchor.y)
    c.rotate(by: angle)
    let rect = CGRect(x: -width / 2, y: 0, width: width, height: height)
    if outlined {
        c.setStrokeColor(color)
        c.setLineWidth(lineWidth)
        c.addEllipse(in: rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        c.strokePath()
    } else {
        c.setFillColor(color)
        c.addEllipse(in: rect)
        c.fillPath()
    }
    c.restoreGState()
}

/// 尖头麦粒：两端收尖，比椭圆更像谷物。
func pointedGrainPath(width: CGFloat, height: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addQuadCurve(to: CGPoint(x: 0, y: height), control: CGPoint(x: width, y: height * 0.52))
    path.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -width, y: height * 0.52))
    path.closeSubpath()
    return path
}

/// 一支麦穗：茎 + 三对麦粒 + 顶粒。
func drawStalk(
    _ c: CGContext,
    base: CGPoint,
    length: CGFloat,
    tilt: CGFloat = 0,
    stemWidth: CGFloat = 26,
    grainScale: CGFloat = 1,
    color: CGColor,
    rows: Int = 3,
    outlined: Bool = false
) {
    c.saveGState()
    c.translateBy(x: base.x, y: base.y)
    c.rotate(by: tilt)

    c.setStrokeColor(color)
    c.setLineWidth(stemWidth)
    c.setLineCap(.round)
    c.move(to: CGPoint(x: 0, y: 0))
    c.addLine(to: CGPoint(x: 0, y: length * 0.9))
    c.strokePath()

    let grainWidth = 88 * grainScale
    let grainHeight = 146 * grainScale

    for row in 0..<rows {
        let y = length * 0.30 + CGFloat(row) * length * 0.185
        for side in [CGFloat(-1), CGFloat(1)] {
            drawGrain(
                c,
                at: CGPoint(x: 0, y: y),
                angle: side * 0.62,
                width: grainWidth,
                height: grainHeight,
                color: color,
                outlined: outlined,
                lineWidth: stemWidth * 0.55
            )
        }
    }

    drawGrain(
        c,
        at: CGPoint(x: 0, y: length * 0.86),
        angle: 0,
        width: grainWidth,
        height: grainHeight * 1.08,
        color: color,
        outlined: outlined,
        lineWidth: stemWidth * 0.55
    )

    c.restoreGState()
}

// MARK: - A 单穗（当前版本，作基准）

func drawSingle(_ c: CGContext) {
    plate(c, 0x1F4D3A, 0x3A8A64)
    drawStalk(c, base: CGPoint(x: 512, y: 208), length: 622, color: rgb(0xF6CE63))
}

// MARK: - B 双穗交叉

func drawDouble(_ c: CGContext) {
    plate(c, 0x1B2B52, 0x2F53A8)
    let gold = rgb(0xF6CE63)
    // 两支从同一点抽出去，形成 V 形束；之前分开站容易在中段糊成一团
    drawStalk(c, base: CGPoint(x: 512, y: 150), length: 660, tilt: 0.24, grainScale: 0.70, color: gold)
    drawStalk(c, base: CGPoint(x: 512, y: 150), length: 660, tilt: -0.24, grainScale: 0.70, color: gold)
}

// MARK: - C 拾落穗

func drawGleaned(_ c: CGContext) {
    plate(c, 0x14231C, 0x2A5040)
    let gold = rgb(0xF6CE63)
    drawStalk(c, base: CGPoint(x: 470, y: 214), length: 596, tilt: -0.05, grainScale: 0.92, color: gold)
    // 掉在地上的一粒——"拾"这个动作的落点
    drawGrain(c, at: CGPoint(x: 646, y: 262), angle: 1.32, width: 96, height: 160, color: gold)
}

// MARK: - D 圆形徽章

func drawBadge(_ c: CGContext) {
    plate(c, 0x3A2116, 0x5E3821)
    let cream = rgb(0xF3DFAE)

    c.setStrokeColor(cream)
    c.setLineWidth(12)
    c.addEllipse(in: CGRect(x: 512 - 288, y: 512 - 288, width: 576, height: 576))
    c.strokePath()

    drawStalk(c, base: CGPoint(x: 512, y: 252), length: 528, stemWidth: 22, grainScale: 0.82, color: cream)
}

// MARK: - E 三粒

func drawThreeGrains(_ c: CGContext) {
    plate(c, 0x2A2E33, 0x14171C)
    let gold = rgb(0xF6CE63)
    let spots: [(CGPoint, CGFloat)] = [
        (CGPoint(x: 424, y: 322), 0.40),
        (CGPoint(x: 512, y: 468), 0.40),
        (CGPoint(x: 600, y: 614), 0.40),
    ]
    for (point, angle) in spots {
        c.saveGState()
        c.translateBy(x: point.x, y: point.y)
        c.rotate(by: angle)
        c.addPath(pointedGrainPath(width: 78, height: 250))
        c.setFillColor(gold)
        c.fillPath()
        c.restoreGState()
    }
}

// MARK: - F 线描

func drawOutline(_ c: CGContext) {
    plate(c, 0x0E0F12, 0x1D2127)
    drawStalk(
        c,
        base: CGPoint(x: 512, y: 198),
        length: 630,
        stemWidth: 26,
        grainScale: 1.08,
        color: rgb(0xE8C976),
        outlined: true
    )
}

// MARK: - 渲染

struct Candidate {
    let letter: String
    let name: String
    let draw: (CGContext) -> Void
}

let candidates: [Candidate] = [
    Candidate(letter: "A", name: "单穗 · 深绿", draw: drawSingle),
    Candidate(letter: "B", name: "双穗 · 藏蓝", draw: drawDouble),
    Candidate(letter: "C", name: "拾落穗", draw: drawGleaned),
    Candidate(letter: "D", name: "徽章 · 暖褐", draw: drawBadge),
    Candidate(letter: "E", name: "三粒", draw: drawThreeGrains),
    Candidate(letter: "F", name: "线描", draw: drawOutline),
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
