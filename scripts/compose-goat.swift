// 山羊图标方案。
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

/// 把白底字形按亮度转成 alpha（qlmanage 出来的是白底不透明 PNG）。
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

func loadGlyph(_ path: String) -> CGImage? {
    guard let image = NSImage(contentsOfFile: path) else { return nil }
    var rect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
    guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
    return matte(cg)
}

func tint(_ glyph: CGImage, color: CGColor) -> CGImage {
    let c = makeContext(1024, 1024)
    c.setFillColor(color)
    c.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    c.setBlendMode(.destinationIn)
    c.draw(glyph, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
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

func place(_ c: CGContext, _ glyph: CGImage, fraction: CGFloat, dy: CGFloat = 0) {
    let side = canvas * fraction
    c.draw(glyph, in: CGRect(x: (canvas - side) / 2, y: (canvas - side) / 2 + dy, width: side, height: side))
}

/// 一丛草：几条带弯的叶片
func grass(_ c: CGContext, at base: CGPoint, height: CGFloat, color: CGColor, blades: [CGFloat]) {
    c.setStrokeColor(color)
    c.setLineWidth(14)
    c.setLineCap(.round)
    for (index, lean) in blades.enumerated() {
        let x = base.x + CGFloat(index) * 46
        c.move(to: CGPoint(x: x, y: base.y))
        c.addQuadCurve(
            to: CGPoint(x: x + lean, y: base.y + height),
            control: CGPoint(x: x + lean * 0.2, y: base.y + height * 0.55)
        )
    }
    c.strokePath()
}

let goatRaw = loadGlyph("/tmp/glyph/png/goat-transparent.svg.png")!
let goatInk = tint(goatRaw, color: rgb(ink))
let goatOchre = tint(goatRaw, color: rgb(ochre))
let goatGold = tint(goatRaw, color: rgb(gold))

func draw1(_ c: CGContext) {
    plate(c, paper, paperDeep)
    place(c, goatInk, fraction: 0.66)
}

func draw2(_ c: CGContext) {
    plate(c, 0x1E3529, 0x35563F)
    place(c, goatGold, fraction: 0.66)
}

func draw3(_ c: CGContext) {
    plate(c, paper, paperDeep)
    place(c, goatInk, fraction: 0.60, dy: 44)
    grass(c, at: CGPoint(x: 268, y: 214), height: 0, color: rgb(0, 0), blades: [])
    // 底部被啃过的草茬：高低不齐
    c.setStrokeColor(rgb(ink, 0.45))
    c.setLineWidth(13)
    c.setLineCap(.round)
    let stubs: [(CGFloat, CGFloat)] = [(276, 58), (320, 88), (364, 44), (408, 72), (452, 52)]
    for (x, h) in stubs {
        c.move(to: CGPoint(x: x, y: 208))
        c.addLine(to: CGPoint(x: x, y: 208 + h))
    }
    c.strokePath()
}

func draw4(_ c: CGContext) {
    plate(c, paper, paperDeep)
    // 圆形底
    c.setFillColor(rgb(0x2C3A2E))
    c.addEllipse(in: CGRect(x: 512 - 296, y: 512 - 296, width: 592, height: 592))
    c.fillPath()
    place(c, goatGold, fraction: 0.56)
}

func draw5(_ c: CGContext) {
    plate(c, paper, paperDeep)
    place(c, goatOchre, fraction: 0.62)
}

func draw6(_ c: CGContext) {
    plate(c, paper, paperDeep)
    place(c, goatInk, fraction: 0.56, dy: 30)
    // 完整的一丛草（还没被吃）
    grass(c, at: CGPoint(x: 640, y: 210), height: 150, color: rgb(ink, 0.5), blades: [-18, 0, 16])
}

let candidates: [(String, String, (CGContext) -> Void)] = [
    ("1", "墨山羊 · 米白", draw1),
    ("2", "金山羊 · 深绿", draw2),
    ("3", "山羊 + 啃过的草茬", draw3),
    ("4", "圆形徽章", draw4),
    ("5", "赭色山羊", draw5),
    ("6", "山羊 + 草丛", draw6),
]

var rendered: [(String, String, CGImage)] = []
for (letter, name, draw) in candidates {
    let c = makeContext(Int(canvas), Int(canvas))
    draw(c)
    guard let image = c.makeImage() else { continue }
    rendered.append((letter, name, image))
    let rep = NSBitmapImageRep(cgImage: image)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(dir)/goat-\(letter).png"))
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
// 每轮输出带时间戳，避免聊天端把同名文件当成同一张图缓存住
let stamp = Int(Date().timeIntervalSince1970)
let unique = "\(dir)/sheet-goat-\(stamp).png"
try? FileManager.default.copyItem(atPath: "\(dir)/contact-sheet.png", toPath: unique)
print("unique: \(unique)")
