// 标注：激光笔 / 画笔 / 荧光笔
// 在主屏源窗口上方盖一层透明面板接收鼠标，坐标按源窗口归一化（0~1，左上角为原点），
// 同一份数据同时画在主屏面板和副屏镜像上。

import AppKit
import Carbon.HIToolbox

enum AnnotationTool: Equatable { case none, laser, pen, highlighter }

struct Stroke {
    var points: [CGPoint]          // 归一化坐标
    var color: NSColor
    var alpha: CGFloat
    var width: CGFloat             // 相对源窗口高度的比例
    var fades: Bool
    var endedAt: CFTimeInterval?

    static let fadeDelay: CFTimeInterval = 2.5
    static let fadeDuration: CFTimeInterval = 0.6

    func opacity(now: CFTimeInterval) -> CGFloat {
        guard fades, let e = endedAt else { return 1 }
        let t = now - e - Stroke.fadeDelay
        return t <= 0 ? 1 : max(0, 1 - CGFloat(t / Stroke.fadeDuration))
    }
}

final class AnnotationModel {
    var tool: AnnotationTool = .none
    var strokes: [Stroke] = []
    var current: Stroke?
    var laser: [(p: CGPoint, t: CFTimeInterval)] = []
    var laserVisible = false
    var color: NSColor = .systemRed
    var autoFade = false

    static let laserTrail: CFTimeInterval = 0.35

    var isAnimating: Bool {
        let now = CACurrentMediaTime()
        if laser.contains(where: { now - $0.t < AnnotationModel.laserTrail }) && laser.count > 1 { return true }
        return strokes.contains { $0.fades && $0.endedAt != nil }
    }

    func prune(now: CFTimeInterval) {
        strokes.removeAll { $0.opacity(now: now) <= 0 }
        if let last = laser.last {
            laser.removeAll { now - $0.t > AnnotationModel.laserTrail }
            if laser.isEmpty { laser = [(last.p, last.t)] }   // 保留最后一个点作为光点位置
        }
    }
}

enum AnnotationRenderer {
    static func draw(_ m: AnnotationModel, in ctx: CGContext, rect: CGRect) {
        guard rect.width > 1, rect.height > 1 else { return }
        let now = CACurrentMediaTime()
        func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.maxY - p.y * rect.height) }

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        var all = m.strokes
        if let c = m.current { all.append(c) }
        for s in all {
            let a = s.opacity(now: now)
            guard a > 0, let first = s.points.first else { continue }
            let path = CGMutablePath()
            path.move(to: pt(first))
            if s.points.count == 1 {
                path.addLine(to: pt(first))
            } else {
                for i in 1..<s.points.count {
                    let p0 = pt(s.points[i - 1]), p1 = pt(s.points[i])
                    path.addQuadCurve(to: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2), control: p0)
                }
                path.addLine(to: pt(s.points[s.points.count - 1]))
            }
            ctx.addPath(path)
            ctx.setLineWidth(max(1, s.width * rect.height))
            ctx.setStrokeColor(s.color.withAlphaComponent(s.alpha * a).cgColor)
            ctx.strokePath()
        }

        // 激光笔：渐隐的尾迹 + 发光的点
        guard m.tool == .laser, m.laserVisible, let head = m.laser.last else { return }
        let r = max(5, rect.height * 0.009)
        let color = m.color
        let trail = m.laser.filter { now - $0.t < AnnotationModel.laserTrail }
        if trail.count > 1 {
            for i in 1..<trail.count {
                let k = 1 - CGFloat((now - trail[i].t) / AnnotationModel.laserTrail)
                guard k > 0 else { continue }
                ctx.setLineWidth(r * 1.4 * k)
                ctx.setStrokeColor(color.withAlphaComponent(0.55 * k).cgColor)
                ctx.move(to: pt(trail[i - 1].p))
                ctx.addLine(to: pt(trail[i].p))
                ctx.strokePath()
            }
        }
        let c = pt(head.p)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 2.5, color: color.withAlphaComponent(0.9).cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        ctx.restoreGState()
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        let ir = r * 0.4
        ctx.fillEllipse(in: CGRect(x: c.x - ir, y: c.y - ir, width: 2 * ir, height: 2 * ir))
    }
}

/// 绘制标注的图层；rectProvider 给出源窗口画面在图层中的位置
final class AnnotationLayer: CALayer {
    var model: AnnotationModel?
    var rectProvider: (() -> CGRect)?

    override init() {
        super.init()
        needsDisplayOnBoundsChange = true
        isOpaque = false
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(in ctx: CGContext) {
        guard let m = model else { return }
        AnnotationRenderer.draw(m, in: ctx, rect: rectProvider?() ?? bounds)
    }
}

// MARK: - 主屏上的透明标注面板

final class OverlayView: NSView {
    let annotationLayer = AnnotationLayer()
    var onBegin: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onEnd: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        layer = root
        wantsLayer = true
        annotationLayer.frame = root.bounds
        annotationLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        root.addSublayer(annotationLayer)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        annotationLayer.contentsScale = window?.backingScaleFactor ?? 2
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    private func norm(_ e: NSEvent) -> CGPoint {
        let p = convert(e.locationInWindow, from: nil)
        return CGPoint(x: p.x / max(1, bounds.width), y: 1 - p.y / max(1, bounds.height))
    }
    override func mouseDown(with e: NSEvent) { onBegin?(norm(e)) }
    override func mouseDragged(with e: NSEvent) { onDrag?(norm(e)) }
    override func mouseUp(with e: NSEvent) { onEnd?() }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 控制器

@MainActor
final class AnnotationController {
    let model = AnnotationModel()
    var sourceWindowID: CGWindowID?
    /// 副屏镜像上的标注图层
    var mirrorLayer: AnnotationLayer?
    var onToolChange: ((AnnotationTool) -> Void)?

    private var panel: OverlayPanel?
    private var overlay: OverlayView?
    private var trackTimer: Timer?
    private var animTimer: Timer?
    private var monitors: [Any] = []
    private var sourceFrame: CGRect = .zero   // Cocoa 全局坐标
    private var dirty = false

    var tool: AnnotationTool { model.tool }

    /// 选中同一工具再按一次 = 退出标注
    func toggle(_ t: AnnotationTool) { setTool(model.tool == t ? .none : t) }

    func setTool(_ t: AnnotationTool) {
        if t != .none && sourceWindowID == nil { NSSound.beep(); return }
        model.tool = t
        if t == .none {
            teardown()
        } else {
            setup()
            panel?.ignoresMouseEvents = (t == .laser)
            // 透明区域默认会让点击穿透，画笔模式下铺一层几乎看不见的底色来接住鼠标
            panel?.backgroundColor = t == .laser ? .clear : NSColor(white: 0, alpha: 0.01)
            if t != .laser { model.laserVisible = false }
        }
        changed()
        onToolChange?(t)
    }

    func undo() {
        if !model.strokes.isEmpty { model.strokes.removeLast(); changed() }
    }

    func clear() {
        model.strokes.removeAll(); model.current = nil; changed()
    }

    func setColor(_ c: NSColor) { model.color = c; changed() }

    // 调试用：注入一笔
    func debugStroke(_ pts: [CGPoint]) {
        guard let f = pts.first else { return }
        begin(f); pts.dropFirst().forEach { drag($0) }; end()
    }
    func debugLaser(_ p: CGPoint) { model.laserVisible = true; model.laser.append((p, CACurrentMediaTime())); changed() }

    // MARK: 内部

    private func setup() {
        if panel == nil {
            let p = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.isReleasedWhenClosed = false
            let v = OverlayView(frame: .zero)
            v.annotationLayer.model = model
            v.onBegin = { [weak self] p in self?.begin(p) }
            v.onDrag = { [weak self] p in self?.drag(p) }
            v.onEnd = { [weak self] in self?.end() }
            p.contentView = v
            panel = p; overlay = v
        }
        trackSource()
        if trackTimer == nil {
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.trackSource() } }
            RunLoop.main.add(t, forMode: .common); trackTimer = t
        }
        if animTimer == nil {
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            RunLoop.main.add(t, forMode: .common); animTimer = t
        }
        if monitors.isEmpty {
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
            if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseMoved() } }) { monitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
                MainActor.assumeIsolated { self?.mouseMoved() }; return e }) { monitors.append(l) }
        }
    }

    private func teardown() {
        trackTimer?.invalidate(); trackTimer = nil
        animTimer?.invalidate(); animTimer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }; monitors.removeAll()
        panel?.orderOut(nil)
        model.strokes.removeAll(); model.current = nil
        model.laser.removeAll(); model.laserVisible = false
    }

    /// 让面板始终贴合源窗口
    private func trackSource() {
        guard let wid = sourceWindowID, let panel,
              let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]])?.first,
              (info[kCGWindowIsOnscreen as String] as? Bool) == true,
              let bd = info[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: bd as CFDictionary)
        else { panel?.orderOut(nil); return }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let f = CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
        if f != sourceFrame || !panel.isVisible {
            sourceFrame = f
            panel.setFrame(f, display: true)
            panel.orderFrontRegardless()
            changed()
        }
    }

    private func mouseMoved() {
        guard model.tool == .laser, sourceFrame.width > 0 else { return }
        let m = NSEvent.mouseLocation
        if sourceFrame.contains(m) {
            let p = CGPoint(x: (m.x - sourceFrame.minX) / sourceFrame.width, y: (sourceFrame.maxY - m.y) / sourceFrame.height)
            model.laserVisible = true
            model.laser.append((p, CACurrentMediaTime()))
        } else {
            model.laserVisible = false
        }
        dirty = true
    }

    private func begin(_ p: CGPoint) {
        let hl = model.tool == .highlighter
        let hpt = max(1, sourceFrame.height)
        model.current = Stroke(points: [p], color: model.color, alpha: hl ? 0.35 : 1,
                               width: (hl ? 22 : 4) / hpt, fades: model.autoFade, endedAt: nil)
        dirty = true
    }
    private func drag(_ p: CGPoint) {
        guard model.current != nil else { return }
        if let last = model.current!.points.last, hypot(last.x - p.x, last.y - p.y) < 0.0008 { return }
        model.current!.points.append(p)
        dirty = true
    }
    private func end() {
        guard var s = model.current else { return }
        s.endedAt = CACurrentMediaTime()
        model.strokes.append(s)
        model.current = nil
        dirty = true
    }

    private func tick() {
        let animating = model.isAnimating
        if animating { model.prune(now: CACurrentMediaTime()) }
        if dirty || animating { changed() }
    }

    private func changed() {
        dirty = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        overlay?.annotationLayer.setNeedsDisplay()
        mirrorLayer?.setNeedsDisplay()
        CATransaction.commit()
    }
}

// MARK: - 全局快捷键（Carbon，无需额外权限）

enum HotKeys {
    nonisolated(unsafe) static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) static var refs: [EventHotKeyRef] = []
    nonisolated(unsafe) static var installed = false

    static func register(_ id: UInt32, keyCode: Int, _ handler: @escaping () -> Void) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                HotKeys.handlers[hk.id]?()
                return noErr
            }, 1, &spec, nil, nil)
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey),
                                         EventHotKeyID(signature: OSType(0x574D4952), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref); handlers[id] = handler }
    }
}
