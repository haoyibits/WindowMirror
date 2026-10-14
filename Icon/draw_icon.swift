// 绘制 WindowMirror 图标（1024×1024 PNG）
// 用法：swift Icon/draw_icon.swift <输出.png>
// 造型：实心小窗口 + 大屏幕线框 + 斜向箭头，表示把窗口放到更大的屏幕上
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)   // 左上角为原点

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }

let top: UInt32 = 0x2FD3C4, bottom: UInt32 = 0x2B63F0, ink: UInt32 = 0x0B2A6B

// 1. 底板（macOS 图标网格：824×824，圆角 185）
let plate = rr(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(plate); ctx.setFillColor(rgb(top)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(plate); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(top), rgb(bottom)] as CFArray, locations: nil)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)] as CFArray, locations: nil)!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 360, y: 150), startRadius: 0,
                       endCenter: CGPoint(x: 360, y: 150), endRadius: 600, options: [])
ctx.restoreGState()

// 2. 大屏幕线框
let big = CGRect(x: 330, y: 230, width: 480, height: 360)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: rgb(ink, 0.35))
ctx.addPath(rr(big, 56)); ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(40); ctx.strokePath()
ctx.restoreGState()

// 3. 实心小窗口（压住大框左下角）
let small = CGRect(x: 200, y: 520, width: 300, height: 230)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(ink, 0.40))
ctx.addPath(rr(small, 44)); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState(); ctx.addPath(rr(small, 44)); ctx.clip()
ctx.setFillColor(rgb(bottom, 0.16)); ctx.fill(CGRect(x: small.minX, y: small.minY, width: small.width, height: 62))
ctx.restoreGState()
for i in 0..<3 {
    ctx.setFillColor(rgb(bottom, 0.75))
    ctx.fillEllipse(in: CGRect(x: small.minX + 34 + CGFloat(i) * 30, y: small.minY + 22, width: 20, height: 20))
}

// 4. 斜向箭头：小窗口 → 大屏幕
let a0 = CGPoint(x: 560, y: 520), a1 = CGPoint(x: 680, y: 400)
ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setLineWidth(34)
ctx.move(to: a0); ctx.addLine(to: a1); ctx.strokePath()
ctx.move(to: CGPoint(x: a1.x - 95, y: a1.y)); ctx.addLine(to: a1); ctx.addLine(to: CGPoint(x: a1.x, y: a1.y + 95)); ctx.strokePath()

let img = ctx.makeImage()!
try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
