// 用专业图标库的麦穗字形 + 自己做底板，拼图标。
// 前提：/tmp/glyph/png 里已有光栅化好的字形 PNG。
import AppKit
import CoreGraphics

let canvas: CGFloat = 1024
let dir = "build/icons"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let paper: UInt32 = 0xF6EFE2
let paperDeep: UInt32 = 0xE7DAC4
let ink: UInt32 = 0x2C3A2E
let ochre: UInt32 = 0xB06A34
let gold: UInt32 = 0xE8C06A

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

/// qlmanage 出的是白底不透明 PNG，先按亮度把它转成 alpha，否则涂色会把整块底板填满。
func matte(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    let c = makeContext(w, h)
    c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = c.data else { return image }
    let p = data.bindMemory(to: UInt8.self, capacity: c.bytesPerRow * h)
    for y in 0..<h {
        for x in 0..<w {
            let i = y * c.bytesPerRow + x * 4
            let lum = (0.299 * Double(p[i]) + 0.587 * Double(p[i + 1]) + 0.114 * Double(p[i + 2])) / 255
            let a = UInt8(max(0, min(255, (1 - lum) * 255)))
            p[i] = a; p[i + 1] = a; p[i + 2] = a; p[i + 3] = a
        }
    }
    return c.makeImage() ?? image
}

func loadGlyph(_ name: String) -> CGImage? {
    guard let image = NSImage(contentsOfFile: "/tmp/glyph/png/\(name).png") else { return nil }
    var rect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
    return matte(cg)
}

/// 把字形涂成指定颜色，并可旋转。
func tint(_ glyph: CGImage, color: CGColor, rotation: CGFloat = 0) -> CGImage {
    let size = 1024
    let c = makeContext(size, size)
    c.translateBy(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
    c.rotate(by: rotation)
    c.translateBy(x: -CGFloat(size) / 2, y: -CGFloat(size) / 2)

    // 先铺满颜色，再用字形的 alpha 保留颜色
    c.setFillColor(color)
    c.fill(CGRect(x: 0, y: 0, width: size, height: size))
    c.setBlendMode(.destinationIn)
    c.draw(glyph, in: CGRect(x: 0, y: 0, width: size, height: size))
    return c.makeImage()!
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
    c.setStrokeColor(rgb(0x000000, 0.08))
    c.setLineWidth(3)
    c.strokePath()
}

/// 居中放字形，fraction 控制占画布比例。
func place(_ c: CGContext, _ glyph: CGImage, fraction: CGFloat, dy: CGFloat = 0) {
    let side = canvas * fraction
    let rect = CGRect(x: (canvas - side) / 2, y: (canvas - side) / 2 + dy, width: side, height: side)
    c.draw(glyph, in: rect)
}

func grainPath(_ w: CGFloat, _ h: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 0))
    p.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: w, y: h * 0.46))
    p.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -w, y: h * 0.46))
    p.closeSubpath()
    return p
}

func drop(_ c: CGContext, at: CGPoint, angle: CGFloat, color: CGColor) {
    c.saveGState()
    c.translateBy(x: at.x, y: at.y)
    c.rotate(by: angle)
    c.addPath(grainPath(54, 104))
    c.setFillColor(color)
    c.fillPath()
    c.restoreGState()
}

// 字形：FontAwesome wheat-awn 原始朝向是斜的，转正
let fa = loadGlyph("fa-wheat.svg")!
let faUpright = tint(fa, color: rgb(ink), rotation: .pi / 4)
let faUprightOchre = tint(fa, color: rgb(ochre), rotation: .pi / 4)
let faUprightGold = tint(fa, color: rgb(gold), rotation: .pi / 4)

// MARK: - 六个方案

func draw1(_ c: CGContext) {
    plate(c, paper, paperDeep)
    place(c, faUpright, fraction: 0.62)
}

func draw2(_ c: CGContext) {
    plate(c, paper, paperDeep)
    place(c, faUprightOchre, fraction: 0.62)
}

func draw3(_ c: CGContext) {
    plate(c, paper, paperDeep)
    place(c, faUpright, fraction: 0.56, dy: 40)
    drop(c, at: CGPoint(x: 636, y: 268), angle: 1.4, color: rgb(ochre))
    drop(c, at: CGPoint(x: 692, y: 320), angle: 1.2, color: rgb(ochre))
    drop(c, at: CGPoint(x: 742, y: 250), angle: 1.5, color: rgb(ochre))
}

func draw4(_ c: CGContext) {
    plate(c, 0x1E3529, 0x35563F)
    place(c, faUprightGold, fraction: 0.62)
}

func draw5(_ c: CGContext) {
    plate(c, paper, paperDeep)
    place(c, faUpright, fraction: 0.5, dy: 52)

    // 麦茬
    c.setStrokeColor(rgb(ink, 0.3))
    c.setLineWidth(16)
    c.setLineCap(.round)
    for x in [304.0, 368.0, 700.0, 760.0] {
        c.move(to: CGPoint(x: CGFloat(x), y: 214))
        c.addLine(to: CGPoint(x: CGFloat(x), y: 300))
    }
    c.strokePath()
    c.setLineWidth(8)
    c.move(to: CGPoint(x: 288, y: 214))
    c.addLine(to: CGPoint(x: 776, y: 214))
    c.strokePath()

    drop(c, at: CGPoint(x: 300, y: 300), angle: 0.6, color: rgb(ochre))
}

func draw6(_ c: CGContext) {
    plate(c, paper, paperDeep)
    // 两株并排
    let side = canvas * 0.46
    c.draw(faUpright, in: CGRect(x: 232, y: 300, width: side, height: side))
    c.draw(faUprightOchre, in: CGRect(x: 436, y: 300, width: side, height: side))
}

let candidates: [(String, String, (CGContext) -> Void)] = [
    ("1", "麦穗 · 墨", draw1),
    ("2", "麦穗 · 赭", draw2),
    ("3", "麦穗 + 落粒", draw3),
    ("4", "深绿底 · 金穗", draw4),
    ("5", "麦茬 + 落粒", draw5),
    ("6", "双株", draw6),
]

var rendered: [(String, String, CGImage)] = []
for (letter, name, draw) in candidates {
    let c = makeContext(Int(canvas), Int(canvas))
    draw(c)
    guard let image = c.makeImage() else { continue }
    rendered.append((letter, name, image))
    let rep = NSBitmapImageRep(cgImage: image)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(letter).png"))
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
    sheet.draw(entry.2, in: CGRect(x: x + (cellWidth - 480) / 2, y: y + 150, width: 480, height: 480))

    let label = "\(entry.0)  \(entry.1)" as NSString
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
print("done")
