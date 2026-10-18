// 「graze」图标 · 第五批：写实的麦穗（带麦芒），米白底墨色
import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let dir = "build/icons"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let paper: UInt32 = 0xF6EFE2
let paperDeep: UInt32 = 0xE7DAC4
let ink: UInt32 = 0x2C3A2E
let ochre: UInt32 = 0xB06A34

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

// MARK: - 麦穗（带芒）

/// 尖头麦粒路径：底端在原点，向上长。
func grainPath(_ w: CGFloat, _ h: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0))
    p.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: w, y: h * 0.46))
    p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -w, y: h * 0.46))
    p.closeSubpath()
    return p
}

/// 画一支麦穗：茎 + 若干对麦粒 + 顶粒，每粒都拖一根麦芒。
func wheatEar(
    _ c: CGContext,
    base: CGPoint,
    height: CGFloat,
    tilt: CGFloat = 0,
    bend: CGFloat = 10,
    stemWidth: CGFloat = 16,
    grainWidth: CGFloat = 74,
    grainHeight: CGFloat = 132,
    pairs: Int = 4,
    awnLength: CGFloat = 118,
    awnWidth: CGFloat = 7,
    bodyColor: CGColor,
    awnColor: CGColor
) {
    c.saveGState()
    c.translateBy(x: base.x, y: base.y)
    c.rotate(by: tilt)

    // 茎（略弯，比直线有生气）
    c.setStrokeColor(bodyColor)
    c.setLineWidth(stemWidth)
    c.setLineCap(.round)
    c.move(to: .zero)
    c.addQuadCurve(
        to: CGPoint(x: bend, y: height * 0.82),
        control: CGPoint(x: -bend * 0.4, y: height * 0.45)
    )
    c.strokePath()

    let earTop = height * 0.86
    let span = earTop - height * 0.30

    for row in 0..<pairs {
        let t = pairs == 1 ? 0 : CGFloat(row) / CGFloat(pairs - 1)
        let y = height * 0.30 + span * t * 0.86
        let x = bend * pow(t, 2) * 0.9

        for side in [CGFloat(-1), CGFloat(1)] {
            c.saveGState()
            c.translateBy(x: x, y: y)
            c.rotate(by: side * 0.60)

            c.addPath(grainPath(grainWidth, grainHeight))
            c.setFillColor(bodyColor)
            c.fillPath()

            // 麦芒：从麦粒尖端继续往外
            c.saveGState()
            c.translateBy(x: 0, y: grainHeight * 0.94)
            c.rotate(by: side * 0.22)
            c.setStrokeColor(awnColor)
            c.setLineWidth(awnWidth)
            c.setLineCap(.round)
            c.move(to: .zero)
            c.addLine(to: CGPoint(x: 0, y: awnLength))
            c.strokePath()
            c.restoreGState()

            c.restoreGState()
        }
    }

    // 顶粒 + 两根芒
    c.saveGState()
    c.translateBy(x: bend, y: earTop - grainHeight * 0.2)
    c.addPath(grainPath(grainWidth * 0.92, grainHeight * 1.1))
    c.setFillColor(bodyColor)
    c.fillPath()

    c.setStrokeColor(awnColor)
    c.setLineWidth(awnWidth)
    c.setLineCap(.round)
    for side in [CGFloat(-1), CGFloat(1)] {
        c.saveGState()
        c.translateBy(x: 0, y: grainHeight * 1.02)
        c.rotate(by: side * 0.30)
        c.move(to: .zero)
        c.addLine(to: CGPoint(x: 0, y: awnLength * 1.05))
        c.strokePath()
        c.restoreGState()
    }
    c.restoreGState()

    c.restoreGState()
}

// MARK: - 1 单穗直立

func drawSingle(_ c: CGContext) {
    plate(c, paper, paperDeep)
    wheatEar(
        c, base: CGPoint(x: 512, y: 176), height: 640,
        bodyColor: rgb(ink), awnColor: rgb(ink, 0.75)
    )
}

// MARK: - 2 单穗自然倾斜

func drawLeaning(_ c: CGContext) {
    plate(c, paper, paperDeep)
    wheatEar(
        c, base: CGPoint(x: 470, y: 168), height: 660, tilt: -0.14, bend: 26,
        grainWidth: 78, grainHeight: 138,
        bodyColor: rgb(ink), awnColor: rgb(ink, 0.7)
    )
}

// MARK: - 3 双穗并立

func drawPair(_ c: CGContext) {
    plate(c, paper, paperDeep)
    wheatEar(
        c, base: CGPoint(x: 420, y: 170), height: 600, tilt: 0.10, bend: 14,
        grainWidth: 64, grainHeight: 118, awnLength: 96,
        bodyColor: rgb(ink), awnColor: rgb(ink, 0.65)
    )
    wheatEar(
        c, base: CGPoint(x: 592, y: 170), height: 650, tilt: -0.08, bend: 18,
        grainWidth: 68, grainHeight: 124, awnLength: 100,
        bodyColor: rgb(ochre), awnColor: rgb(ochre, 0.65)
    )
}

// MARK: - 4 穗 + 脚边散落的粒

func drawWithGrains(_ c: CGContext) {
    plate(c, paper, paperDeep)
    wheatEar(
        c, base: CGPoint(x: 470, y: 250), height: 560, tilt: -0.06, bend: 18,
        grainWidth: 72, grainHeight: 128, awnLength: 108,
        bodyColor: rgb(ink), awnColor: rgb(ink, 0.7)
    )

    // 掉在地上的三粒（就是"拾"的对象）
    let drops: [(CGPoint, CGFloat)] = [
        (CGPoint(x: 646, y: 232), 1.35),
        (CGPoint(x: 700, y: 286), 1.15),
        (CGPoint(x: 744, y: 214), 1.45),
    ]
    for (anchor, angle) in drops {
        c.saveGState()
        c.translateBy(x: anchor.x, y: anchor.y)
        c.rotate(by: angle)
        c.addPath(grainPath(52, 96))
        c.setFillColor(rgb(ochre))
        c.fillPath()
        c.restoreGState()
    }
}

// MARK: - 5 穗特写（只画上半截）

func drawCloseUp(_ c: CGContext) {
    plate(c, paper, paperDeep)
    wheatEar(
        c, base: CGPoint(x: 512, y: 120), height: 470,
        stemWidth: 20, grainWidth: 96, grainHeight: 168, pairs: 4, awnLength: 150, awnWidth: 9,
        bodyColor: rgb(ink), awnColor: rgb(ink, 0.7)
    )
    // 茎在底部延伸出画
    c.setStrokeColor(rgb(ink))
    c.setLineWidth(20)
    c.setLineCap(.round)
    c.move(to: CGPoint(x: 512, y: 120))
    c.addLine(to: CGPoint(x: 512, y: 150))
    c.strokePath()
}

// MARK: - 6 麦茬 + 一支穗

func drawStubble(_ c: CGContext) {
    plate(c, paper, paperDeep)

    // 割过的麦茬
    c.setStrokeColor(rgb(ink, 0.28))
    c.setLineWidth(14)
    c.setLineCap(.round)
    for x in [300.0, 356.0, 412.0, 660.0] {
        c.move(to: CGPoint(x: CGFloat(x), y: 210))
        c.addLine(to: CGPoint(x: CGFloat(x), y: 300))
    }
    c.strokePath()

    c.setStrokeColor(rgb(ink, 0.28))
    c.setLineWidth(8)
    c.move(to: CGPoint(x: 280, y: 210))
    c.addLine(to: CGPoint(x: 744, y: 210))
    c.strokePath()

    wheatEar(
        c, base: CGPoint(x: 540, y: 210), height: 600, tilt: 0.04, bend: 16,
        grainWidth: 74, grainHeight: 130, awnLength: 110,
        bodyColor: rgb(ink), awnColor: rgb(ink, 0.7)
    )

    // 倒在地上的一支
    c.saveGState()
    c.translateBy(x: 646, y: 196)
    c.rotate(by: 1.42)
    c.addPath(grainPath(60, 300))
    c.setFillColor(rgb(ochre))
    c.fillPath()
    c.restoreGState()
}

// MARK: - 渲染

struct Candidate {
    let letter: String
    let name: String
    let draw: (CGContext) -> Void
}

let candidates: [Candidate] = [
    Candidate(letter: "1", name: "单穗直立", draw: drawSingle),
    Candidate(letter: "2", name: "单穗倾斜", draw: drawLeaning),
    Candidate(letter: "3", name: "双穗", draw: drawPair),
    Candidate(letter: "4", name: "穗 + 落粒", draw: drawWithGrains),
    Candidate(letter: "5", name: "穗特写", draw: drawCloseUp),
    Candidate(letter: "6", name: "麦茬 + 穗", draw: drawStubble),
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

// 小尺寸验证：16 / 32 / 64 px
let strip = makeContext(1200, 400)
strip.setFillColor(rgb(paperDeep))
strip.fill(CGRect(x: 0, y: 0, width: 1200, height: 400))
strip.interpolationQuality = .none
for (index, size) in [16, 32, 64].enumerated() {
    let small = makeContext(size, size)
    small.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawWithGrains(small)
    guard let image = small.makeImage() else { continue }
    let up = CGFloat(size) * 4
    strip.draw(image, in: CGRect(x: 120 + CGFloat(index) * 360, y: 200 - up / 2, width: up, height: up))
}
if let image = strip.makeImage() {
    let rep = NSBitmapImageRep(cgImage: image)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/small-check.png"))
    }
}
