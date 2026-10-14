// 生成 WindowMirror 图标（1024×1024 PNG）
// 用法：swift Icon/draw_icon.swift <输出.png>
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// 采用左上角为原点的坐标，方便排版
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
func linear(_ path: CGPath, _ c1: CGColor, _ c2: CGColor, from p1: CGPoint, to p2: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: p1, end: p2, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// 1. 底板（macOS 图标网格：824×824，圆角 185）
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(rr(plate, 185)); ctx.setFillColor(rgb(0x3B4BE0)); ctx.fillPath()
ctx.restoreGState()
linear(rr(plate, 185), rgb(0x5A8BFF), rgb(0x5B33D6), from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
// 顶部柔光
ctx.saveGState(); ctx.addPath(rr(plate, 185)); ctx.clip()
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 360, y: 160), startRadius: 0,
                       endCenter: CGPoint(x: 360, y: 160), endRadius: 560, options: [])
ctx.restoreGState()

// 2. 显示器
struct Monitor { let screen: CGRect }
func drawMonitor(_ screen: CGRect, bezel: CGFloat = 16) {
    let body = screen.insetBy(dx: -bezel, dy: -bezel)
    // 支架
    let neckW: CGFloat = screen.width * 0.16
    let neck = CGRect(x: body.midX - neckW / 2, y: body.maxY - 4, width: neckW, height: 50)
    linear(CGPath(rect: neck, transform: nil), rgb(0xDCE3F5), rgb(0xB9C3DE), from: CGPoint(x: neck.minX, y: 0), to: CGPoint(x: neck.maxX, y: 0))
    let base = CGRect(x: body.midX - screen.width * 0.24, y: neck.maxY - 6, width: screen.width * 0.48, height: 16)
    ctx.addPath(rr(base, 8)); ctx.setFillColor(rgb(0xE8EDF9)); ctx.fillPath()
    // 机身
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x1A1060, 0.35))
    ctx.addPath(rr(body, 26)); ctx.setFillColor(rgb(0xF4F6FC)); ctx.fillPath()
    ctx.restoreGState()
    // 屏幕
    linear(rr(screen, 12), rgb(0x1E2547), rgb(0x2B2F63), from: CGPoint(x: 0, y: screen.minY), to: CGPoint(x: 0, y: screen.maxY))
}

// 小窗口（橙色标题栏 + 内容行）
func drawWindow(_ r: CGRect, scale k: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4 * k), blur: 10 * k, color: rgb(0x000000, 0.35))
    ctx.addPath(rr(r, 9 * k)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(rr(r, 9 * k)); ctx.clip()
    let bar = CGRect(x: r.minX, y: r.minY, width: r.width, height: 22 * k)
    linear(CGPath(rect: bar, transform: nil), rgb(0xFFB547), rgb(0xFF7A3D), from: CGPoint(x: bar.minX, y: 0), to: CGPoint(x: bar.maxX, y: 0))
    ctx.restoreGState()
    // 红绿灯
    for (i, c) in [0xFFFFFF, 0xFFFFFF, 0xFFFFFF].enumerated() {
        let d = 7 * k
        ctx.setFillColor(rgb(UInt32(c), 0.85))
        ctx.fillEllipse(in: CGRect(x: r.minX + 9 * k + CGFloat(i) * 11 * k, y: r.minY + 7.5 * k, width: d, height: d))
    }
    // 内容
    let pad = 12 * k
    var y = r.minY + 22 * k + pad
    let widths: [CGFloat] = [0.78, 0.55, 0.68]
    for w in widths where y + 8 * k < r.maxY - pad / 2 {
        ctx.addPath(rr(CGRect(x: r.minX + pad, y: y, width: (r.width - 2 * pad) * w, height: 8 * k), 4 * k))
        ctx.setFillColor(rgb(0x7C86B8, 0.55)); ctx.fillPath()
        y += 16 * k
    }
}

let leftScreen = CGRect(x: 168, y: 470, width: 300, height: 196)
let rightScreen = CGRect(x: 548, y: 418, width: 312, height: 248)
drawMonitor(leftScreen)
drawMonitor(rightScreen)

// 左屏：几个暗色窗口 + 被选中的橙色窗口
ctx.addPath(rr(CGRect(x: 186, y: 486, width: 120, height: 80), 8)); ctx.setFillColor(rgb(0xFFFFFF, 0.10)); ctx.fillPath()
ctx.addPath(rr(CGRect(x: 330, y: 580, width: 120, height: 70), 8)); ctx.setFillColor(rgb(0xFFFFFF, 0.10)); ctx.fillPath()
let srcWin = CGRect(x: 262, y: 528, width: 132, height: 96)
drawWindow(srcWin, scale: 1.0)
// 选中高亮框
ctx.addPath(rr(srcWin.insetBy(dx: -6, dy: -6), 13)); ctx.setStrokeColor(rgb(0xFFD166)); ctx.setLineWidth(4); ctx.strokePath()

// 右屏：同一窗口铺满
drawWindow(rightScreen.insetBy(dx: 14, dy: 14), scale: 1.85)

// 3. 弧形箭头：左窗口 → 右屏
let start = CGPoint(x: srcWin.midX, y: srcWin.minY - 18)
let end = CGPoint(x: rightScreen.midX - 10, y: rightScreen.minY - 46)
let arrow = CGMutablePath()
arrow.move(to: start)
arrow.addCurve(to: end, control1: CGPoint(x: start.x + 10, y: 250), control2: CGPoint(x: end.x - 40, y: 230))
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: rgb(0x1A1060, 0.35))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)
ctx.addPath(arrow); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(22); ctx.setLineCap(.round); ctx.strokePath()
// 箭头头部（方向取曲线末端切线）
let dir = CGPoint(x: end.x - (end.x - 40), y: end.y - 230)
let len = hypot(dir.x, dir.y); let ux = dir.x / len, uy = dir.y / len
let tip = CGPoint(x: end.x + ux * 40, y: end.y + uy * 40)
let wing: CGFloat = 38
let head = CGMutablePath()
head.move(to: tip)
head.addLine(to: CGPoint(x: end.x - uy * wing, y: end.y + ux * wing))
head.addLine(to: CGPoint(x: end.x + uy * wing, y: end.y - ux * wing))
head.closeSubpath()
ctx.addPath(head); ctx.setFillColor(rgb(0xFFFFFF)); ctx.setLineJoin(.round); ctx.setLineWidth(10)
ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.drawPath(using: .fillStroke)
ctx.endTransparencyLayer()
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
