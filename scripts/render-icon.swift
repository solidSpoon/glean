// 「拾穗」意象探索。用法：swift scripts/render-icon.swift
import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let dir = "build/icons"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let gold: UInt32 = 0xE8C976
let goldBright: UInt32 = 0xF6CE63
let cream: UInt32 = 0xF3DFAE

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
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

func white(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }

func plate(_ c: CGContext, _ from: UInt32, _ to: UInt32) {
    let inset: CGFloat = 88
    let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: 196, cornerHeight: 196, transform: nil)

    c.saveGState()
    c.addPath(path)
    c.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if let gradient = CGGradient(colorsSpace: space, colors: [rgb(from), rgb(to)] as CFArray, locations: [0, 1]) {
        c.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    if let gloss = CGGradient(
        colorsSpace: space,
        colors: [white(0.13), white(0)] as CFArray,
        locations: [0, 1]
    ) {
        c.drawLinearGradient(gloss, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])
    }
    c.restoreGState()

    c.addPath(path)
    c.setStrokeColor(white(0.12))
    c.setLineWidth(3)
    c.strokePath()
}

// MARK: - 基元

func grain(
    _ c: CGContext, at anchor: CGPoint, angle: CGFloat,
    width: CGFloat, height: CGFloat, color: CGColor
) {
    c.saveGState()
    c.translateBy(x: anchor.x, y: anchor.y)
    c.rotate(by: angle)
    c.setFillColor(color)
    c.addEllipse(in: CGRect(x: -width / 2, y: 0, width: width, height: height))
    c.fillPath()
    c.restoreGState()
}

/// 一支麦穗：茎 + rows 对麦粒 + 顶粒。base 是茎的落点。
func stalk(
    _ c: CGContext, base: CGPoint, length: CGFloat, tilt: CGFloat = 0,
    stemWidth: CGFloat = 26, grainScale: CGFloat = 1, color: CGColor,
    rows: Int = 3, withStem: Bool = true
) {
    c.saveGState()
    c.translateBy(x: base.x, y: base.y)
    c.rotate(by: tilt)

    if withStem {
        c.setStrokeColor(color)
        c.setLineWidth(stemWidth)
        c.setLineCap(.round)
        c.move(to: .zero)
        c.addLine(to: CGPoint(x: 0, y: length * 0.9))
        c.strokePath()
    }

    let w = 88 * grainScale
    let h = 146 * grainScale
    for row in 0..<rows {
        let y = length * 0.30 + CGFloat(row) * length * 0.185
        for side in [CGFloat(-1), CGFloat(1)] {
            grain(c, at: CGPoint(x: 0, y: y), angle: side * 0.62, width: w, height: h, color: color)
        }
    }
    grain(c, at: CGPoint(x: 0, y: length * 0.86), angle: 0, width: w, height: h * 1.08, color: color)

    c.restoreGState()
}

func groundLine(_ c: CGContext, y: CGFloat, x0: CGFloat, x1: CGFloat, alpha: CGFloat = 0.4, width: CGFloat = 12) {
    c.setStrokeColor(rgb(gold, alpha))
    c.setLineWidth(width)
    c.setLineCap(.round)
    c.move(to: CGPoint(x: x0, y: y))
    c.addLine(to: CGPoint(x: x1, y: y))
    c.strokePath()
}

/// 躺在地上的麦穗：横茎 + 上下交错的麦粒。直接旋转“立穗”会很难看。
func lyingEar(_ c: CGContext, from start: CGPoint, length: CGFloat, scale: CGFloat, color: CGColor) {
    c.setStrokeColor(color)
    c.setLineWidth(16 * scale)
    c.setLineCap(.round)
    c.move(to: start)
    c.addLine(to: CGPoint(x: start.x + length, y: start.y))
    c.strokePath()

    for i in 0..<4 {
        let x = start.x + length * 0.22 + CGFloat(i) * length * 0.17
        for side in [CGFloat(1), CGFloat(-1)] {
            grain(
                c, at: CGPoint(x: x, y: start.y), angle: side * 0.95,
                width: 62 * scale, height: 104 * scale, color: color
            )
        }
    }
    grain(
        c, at: CGPoint(x: start.x + length, y: start.y), angle: 1.45,
        width: 62 * scale, height: 104 * scale, color: color
    )
}

func check(_ c: CGContext, center: CGPoint, size: CGFloat, color: CGColor, width: CGFloat) {
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: center.x - size * 0.5, y: center.y))
    c.addLine(to: CGPoint(x: center.x - size * 0.1, y: center.y - size * 0.42))
    c.addLine(to: CGPoint(x: center.x + size * 0.55, y: center.y + size * 0.5))
    c.strokePath()
}

// MARK: - 1 落穗：一支还立着，一支躺在地上

func drawFallen() {
    return
}

func drawGleanGround(_ c: CGContext) {
    plate(c, 0x1B3A2C, 0x2F6B4F)
    groundLine(c, y: 274, x0: 286, x1: 742)
    stalk(c, base: CGPoint(x: 398, y: 274), length: 520, tilt: -0.05, grainScale: 0.80, color: rgb(goldBright))
    // 倒地的一支：横躺着，不要用旋转的立穗
    lyingEar(c, from: CGPoint(x: 556, y: 286), length: 316, scale: 0.78, color: rgb(goldBright))
}

// MARK: - 2 篮子：拾到的东西收进去了

func drawBasket(_ c: CGContext) {
    plate(c, 0x22352B, 0x40694F)
    let line = rgb(goldBright)

    // 篮身
    let body = CGMutablePath()
    body.move(to: CGPoint(x: 300, y: 430))
    body.addLine(to: CGPoint(x: 724, y: 430))
    body.addLine(to: CGPoint(x: 646, y: 250))
    body.addQuadCurve(to: CGPoint(x: 590, y: 216), control: CGPoint(x: 640, y: 214))
    body.addLine(to: CGPoint(x: 434, y: 216))
    body.addQuadCurve(to: CGPoint(x: 378, y: 250), control: CGPoint(x: 384, y: 214))
    body.closeSubpath()

    c.addPath(body)
    c.setFillColor(rgb(goldBright, 0.18))
    c.fillPath()
    c.addPath(body)
    c.setStrokeColor(line)
    c.setLineWidth(26)
    c.setLineJoin(.round)
    c.strokePath()

    // 提手
    c.setStrokeColor(line)
    c.setLineWidth(24)
    c.setLineCap(.round)
    c.move(to: CGPoint(x: 372, y: 430))
    c.addQuadCurve(to: CGPoint(x: 652, y: 430), control: CGPoint(x: 512, y: 610))
    c.strokePath()

    // 篮里伸出来的穗
    stalk(c, base: CGPoint(x: 500, y: 300), length: 430, tilt: 0.16, stemWidth: 22, grainScale: 0.66, color: line)
}

// MARK: - 3 穗 + 勾：拾起来的那一支

func drawCheck(_ c: CGContext) {
    plate(c, 0x1D3327, 0x35604A)
    stalk(c, base: CGPoint(x: 424, y: 236), length: 500, tilt: 0.02, grainScale: 0.8, color: rgb(goldBright))
    check(c, center: CGPoint(x: 636, y: 396), size: 190, color: rgb(cream), width: 40)
}

// MARK: - 4 倾斜的筛：筛出来的才是要的

func drawSift(_ c: CGContext) {
    plate(c, 0x2A2E33, 0x14171C)
    let line = rgb(goldBright)
    let center = CGPoint(x: 512, y: 600)
    let radius: CGFloat = 258

    c.saveGState()
    c.translateBy(x: center.x, y: center.y)
    c.rotate(by: -0.16)

    c.setStrokeColor(line)
    c.setLineWidth(24)
    c.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
    c.strokePath()

    // 筛网（裁在圆里）
    c.saveGState()
    c.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
    c.clip()
    c.setLineWidth(10)
    c.setStrokeColor(rgb(gold, 0.5))
    for i in -1...1 {
        let offset = CGFloat(i) * 118
        c.move(to: CGPoint(x: offset, y: -radius))
        c.addLine(to: CGPoint(x: offset, y: radius))
        c.move(to: CGPoint(x: -radius, y: offset))
        c.addLine(to: CGPoint(x: radius, y: offset))
    }
    c.strokePath()
    c.restoreGState()

    // 筛里剩下的几粒
    c.setFillColor(line)
    let spots: [CGPoint] = [CGPoint(x: -70, y: 40), CGPoint(x: 50, y: 90), CGPoint(x: 96, y: -50)]
    for spot in spots {
        c.addEllipse(in: CGRect(x: spot.x - 26, y: spot.y - 34, width: 52, height: 68))
    }
    c.fillPath()

    c.restoreGState()

    // 筛下来的一粒
    grain(c, at: CGPoint(x: 560, y: 226), angle: 0.9, width: 62, height: 104, color: rgb(goldBright, 0.85))
}

// MARK: - 5 麦茬 + 落穗：收割之后的田

func drawStubble(_ c: CGContext) {
    plate(c, 0x1B3A2C, 0x2F6B4F)
    groundLine(c, y: 280, x0: 282, x1: 742)

    // 三道麦茬（比之前高，否则像地面上的刮痕）
    c.setStrokeColor(rgb(gold, 0.42))
    c.setLineWidth(22)
    c.setLineCap(.round)
    for x in [330.0, 392.0, 454.0] {
        c.move(to: CGPoint(x: CGFloat(x), y: 280))
        c.addLine(to: CGPoint(x: CGFloat(x), y: 402))
    }
    c.strokePath()

    stalk(c, base: CGPoint(x: 596, y: 280), length: 486, tilt: 0.04, grainScale: 0.78, color: rgb(goldBright))
    lyingEar(c, from: CGPoint(x: 668, y: 292), length: 184, scale: 0.56, color: rgb(goldBright))
}

// MARK: - 6 扎成一束 vs 散落一支

func drawScattered(_ c: CGContext) {
    plate(c, 0x23301F, 0x46603A)
    let line = rgb(goldBright)

    stalk(c, base: CGPoint(x: 470, y: 240), length: 540, tilt: 0.0, grainScale: 0.86, color: line)

    // 脚边散落的几粒（拾的就是这些）
    let spots: [(CGPoint, CGFloat)] = [
        (CGPoint(x: 606, y: 300), 0.55),
        (CGPoint(x: 668, y: 246), 1.25),
        (CGPoint(x: 730, y: 320), 0.30),
    ]
    for (point, angle) in spots {
        grain(c, at: point, angle: angle, width: 62, height: 108, color: line)
    }
}

// MARK: - 渲染

struct Candidate {
    let letter: String
    let name: String
    let draw: (CGContext) -> Void
}

let candidates: [Candidate] = [
    Candidate(letter: "1", name: "落穗 + 地平线", draw: drawGleanGround),
    Candidate(letter: "2", name: "篮子", draw: drawBasket),
    Candidate(letter: "3", name: "穗 + 勾", draw: drawCheck),
    Candidate(letter: "4", name: "倾斜筛", draw: drawSift),
    Candidate(letter: "5", name: "麦茬 + 落穗", draw: drawStubble),
    Candidate(letter: "6", name: "穗 + 散落", draw: drawScattered),
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

let sheet = makeContext(Int(cellWidth) * cols, Int(cellHeight) * rows)
sheet.setFillColor(rgb(0x111418))
sheet.fill(CGRect(x: 0, y: 0, width: CGFloat(Int(cellWidth) * cols), height: CGFloat(Int(cellHeight) * rows)))

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)

for (index, entry) in rendered.enumerated() {
    let col = index % cols
    let row = index / cols
    let x = CGFloat(col) * cellWidth
    let y = CGFloat(rows - 1 - row) * cellHeight

    sheet.draw(entry.1, in: CGRect(x: x + (cellWidth - 480) / 2, y: y + 150, width: 480, height: 480))

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
