// Annotation: laser pointer / pen / highlighter
// A transparent panel over the source window on the main screen receives the mouse. Coordinates are
// normalized to the source window (0–1, top-left origin), and the same data is drawn both on that panel
// and on the mirror on the secondary display.

import AppKit
import Carbon.HIToolbox

enum AnnotationTool: Equatable { case none, laser, pen, highlighter }

struct Stroke {
    var points: [CGPoint]          // Normalized coordinates
    var color: NSColor
    var alpha: CGFloat
    var width: CGFloat             // Fraction of the source window height
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
            if laser.isEmpty { laser = [(last.p, last.t)] }   // Keep the last point as the dot position
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

        // Laser: fading trail + glowing dot
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

/// Layer that draws annotations; rectProvider gives where the source image sits in the layer
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

// MARK: - Transparent annotation panel on the main screen

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

// MARK: - Controller

@MainActor
final class AnnotationController {
    let model = AnnotationModel()
    var sourceWindowID: CGWindowID?
    /// Annotation layer on the mirror on the secondary display
    var mirrorLayer: AnnotationLayer?
    var onToolChange: ((AnnotationTool) -> Void)?

    private var panel: OverlayPanel?
    private var overlay: OverlayView?
    private var trackTimer: Timer?
    private var animTimer: Timer?
    private var monitors: [Any] = []
    private var sourceFrame: CGRect = .zero   // Cocoa global coordinates
    private var dirty = false

    var tool: AnnotationTool { model.tool }

    /// Choosing the active tool again exits annotation
    func toggle(_ t: AnnotationTool) { setTool(model.tool == t ? .none : t) }

    func setTool(_ t: AnnotationTool) {
        if t != .none && sourceWindowID == nil { NSSound.beep(); return }
        model.tool = t
        if t == .none {
            teardown()
        } else {
            setup()
            panel?.ignoresMouseEvents = (t == .laser)
            // Clicks pass through transparent areas, so in drawing modes use a nearly invisible background to catch the mouse
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

    // Debug: inject a stroke
    func debugStroke(_ pts: [CGPoint]) {
        guard let f = pts.first else { return }
        begin(f); pts.dropFirst().forEach { drag($0) }; end()
    }
    func debugLaser(_ p: CGPoint) { model.laserVisible = true; model.laser.append((p, CACurrentMediaTime())); changed() }

    // MARK: Internals

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

    /// Keeps the panel aligned with the source window
    private func trackSource() {
        guard let wid = sourceWindowID, let panel, let f = onScreenFrame(of: wid)
        else { panel?.orderOut(nil); return }
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

// MARK: - Global hotkeys (Carbon, no extra permission needed)

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
