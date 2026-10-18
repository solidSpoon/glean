// 「glean」图标 · 第四批：符号型，米白底 + 墨色
import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let dir = "build/icons"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let ink: UInt32 = 0x23302A
let accent: UInt32 = 0xC2622F
let paper: UInt32 = 0xF5EEE1
let paperDeep: UInt32 = 0xE3D5BE

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
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

func plate(_ c: CGContext, _ from: UInt32, _ to: UInt32) {
    let inset: CGFloat = 88
    let rect = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: 196, cornerHeight: 196, transform: nil)

    c.saveGState()
    c.addPath(path)
    c.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    if let g = CGGradient(colorsSpace: space, colors: [rgb(from), rgb(to)] as CFArray, locations: [0, 1]) {
        c.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    }
    c.restoreGState()

    c.addPath(path)
    c.setStrokeColor(rgb(ink, 0.10))
    c.setLineWidth(3)
    c.strokePath()
}

func grainPath(_ width: CGFloat, _ height: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0))
    p.addQuadCurve(to: CGPoint(x: 0, y: height), control: CGPoint(x: width, y: height * 0.5))
    p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -width, y: height * 0.5))
    p.closeSubpath()
    return p
}

func fillGrain(_ c: CGContext, at anchor: CGPoint, angle: CGFloat, w: CGFloat, h: CGFloat, color: CGColor) {
    c.saveGState()
    c.translateBy(x: anchor.x, y: anchor.y)
    c.rotate(by: angle)
    c.addPath(grainPath(w, h))
    c.setFillColor(color)
    c.fillPath()
    c.restoreGState()
}

func strokeGrain(_ c: CGContext, at anchor: CGPoint, angle: CGFloat, w: CGFloat, h: CGFloat, width: CGFloat, color: CGColor) {
    c.saveGState()
    c.translateBy(x: anchor.x, y: anchor.y)
    c.rotate(by: angle)
    c.addPath(grainPath(w, h))
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.setLineJoin(.round)
    c.strokePath()
    c.restoreGState()
}

// MARK: - 1 墨粒 + 挖空勾

func drawGrainCheck(_ c: CGContext) {
    plate(c, paper, paperDeep)

    c.saveGState()
    c.translateBy(x: 512, y: 236)
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(ink, 0.30))
    c.addPath(grainPath(216, 512))
    c.setFillColor(rgb(ink))
    c.fillPath()
    c.restoreGState()

    c.setStrokeColor(rgb(paper))
    c.setLineWidth(46)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 432, y: 470))
    c.addLine(to: CGPoint(x: 492, y: 402))
    c.addLine(to: CGPoint(x: 598, y: 538))
    c.strokePath()
}

// MARK: - 2 粗笔几何穗

func drawEarMark(_ c: CGContext) {
    plate(c, paper, paperDeep)
    let line = rgb(ink)

    c.setStrokeColor(line)
    c.setLineWidth(40)
    c.setLineCap(.round)
    c.move(to: CGPoint(x: 512, y: 246))
    c.addLine(to: CGPoint(x: 512, y: 690))
    c.strokePath()

    c.setLineWidth(38)
    for row in 0..<3 {
        let y = 372.0 + CGFloat(row) * 104
        for side in [CGFloat(-1), CGFloat(1)] {
            c.move(to: CGPoint(x: 512, y: y))
            c.addLine(to: CGPoint(x: 512 + side * 132, y: y + 104))
        }
    }
    c.strokePath()

    // 顶端一粒，让符号有个重点
    fillGrain(c, at: CGPoint(x: 512, y: 726), angle: 0, w: 96, h: 150, color: rgb(accent))
}

// MARK: - 3 实心粒 + 描边重影

func drawGhost(_ c: CGContext) {
    plate(c, paper, paperDeep)

    strokeGrain(c, at: CGPoint(x: 392, y: 384), angle: 0.22, w: 150, h: 340, width: 20, color: rgb(ink, 0.35))
    fillGrain(c, at: CGPoint(x: 556, y: 300), angle: 0, w: 178, h: 420, color: rgb(ink))
}

// MARK: - 4 一排里挑出一粒

func drawLifted(_ c: CGContext) {
    plate(c, paper, paperDeep)

    let xs: [CGFloat] = [330, 400, 624, 694]
    for x in xs {
        strokeGrain(c, at: CGPoint(x: x, y: 330), angle: 0, w: 62, h: 150, width: 16, color: rgb(ink, 0.45))
    }

    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(ink, 0.28))
    fillGrain(c, at: CGPoint(x: 512, y: 340), angle: 0, w: 150, h: 372, color: rgb(accent))
    c.restoreGState()
}

// MARK: - 5 带芒的一粒

func drawAwned(_ c: CGContext) {
    plate(c, paper, paperDeep)

    fillGrain(c, at: CGPoint(x: 512, y: 262), angle: 0, w: 172, h: 392, color: rgb(ink))

    c.setStrokeColor(rgb(accent))
    c.setLineWidth(30)
    c.setLineCap(.round)
    c.move(to: CGPoint(x: 512, y: 690))
    c.addLine(to: CGPoint(x: 404, y: 826))
    c.move(to: CGPoint(x: 512, y: 690))
    c.addLine(to: CGPoint(x: 620, y: 826))
    c.strokePath()
}

// MARK: - 6 印章

func drawSeal(_ c: CGContext) {
    plate(c, paper, paperDeep)

    c.setStrokeColor(rgb(ink))
    c.setLineWidth(30)
    c.addEllipse(in: CGRect(x: 512 - 282, y: 512 - 282, width: 564, height: 564))
    c.strokePath()

    fillGrain(c, at: CGPoint(x: 512, y: 636), angle: 0, w: 128, h: 300, color: rgb(accent))

    c.setStrokeColor(rgb(ink, 0.8))
    c.setLineWidth(26)
    c.setLineCap(.round)
    c.move(to: CGPoint(x: 420, y: 340))
    c.addLine(to: CGPoint(x: 604, y: 340))
    c.strokePath()
}

// MARK: - 渲染

struct Candidate {
    let letter: String
    let name: String
    let draw: (CGContext) -> Void
}

let candidates: [Candidate] = [
    Candidate(letter: "1", name: "墨粒 + 勾", draw: drawGrainCheck),
    Candidate(letter: "2", name: "几何穗", draw: drawEarMark),
    Candidate(letter: "3", name: "实粒 + 重影", draw: drawGhost),
    Candidate(letter: "4", name: "一排挑一粒", draw: drawLifted),
    Candidate(letter: "5", name: "芒粒", draw: drawAwned),
    Candidate(letter: "6", name: "印章", draw: drawSeal),
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

let cellWidth: CGFloat = 620
let cellHeight: CGFloat = 760
let cols = 3, rows = 2

let sheet = makeContext(Int(cellWidth) * cols, Int(cellHeight) * rows)
sheet.setFillColor(rgb(0x111418))
sheet.fill(CGRect(x: 0, y: 0, width: CGFloat(Int(cellWidth) * cols), height: CGFloat(Int(cellHeight) * rows)))

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)

for (index, entry) in rendered.enumerated() {
    let x = CGFloat(index % cols) * cellWidth
    let y = CGFloat(rows - 1 - index / cols) * cellHeight
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

if let image = sheet.makeImage() {
    let rep = NSBitmapImageRep(cgImage: image)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/contact-sheet.png"))
    }
}

print("rendered \(rendered.count) → \(dir)")

// MARK: - 小尺寸验证：16 / 32 / 64 px 放大看轮廓是否还成立
let sizes: [Int] = [16, 32, 64]
let strip = makeContext(1200, 400)
strip.setFillColor(rgb(0xEDE4D2))
strip.fill(CGRect(x: 0, y: 0, width: 1200, height: 400))
strip.interpolationQuality = .none

for (index, size) in sizes.enumerated() {
    let small = makeContext(size, size)
    small.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawGrainCheck(small)
    guard let image = small.makeImage() else { continue }
    let up = CGFloat(size) * 4
    let x = 120 + CGFloat(index) * 360
    strip.draw(image, in: CGRect(x: x, y: 200 - up / 2, width: up, height: up))
}

if let image = strip.makeImage() {
    let rep = NSBitmapImageRep(cgImage: image)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/small-check.png"))
    }
}
