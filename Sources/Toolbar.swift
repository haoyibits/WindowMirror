// Floating toolbar above the source window on the main screen: annotation tools, color, undo/clear,
// fitting the source window to the target, and stopping the mirror.
// It sits just above the window's top edge (or inside it when there's no room) and follows it around.
// Outside annotation it stays directly above the source window in the window order, so windows that
// cover the source cover the toolbar too. It is never captured: the stream only includes the source window.

import AppKit

final class ToolbarButton: NSButton {
    var isActive = false { didSet { updateBackground() } }
    private var hovering = false { didSet { updateBackground() } }

    init(symbol: String, target: AnyObject, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        self.target = target
        self.action = action
        isBordered = false
        imagePosition = .imageOnly
        setSymbol(symbol)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSymbol(_ name: String) {
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func updateBackground() {
        let c: NSColor? = isActive ? .controlAccentColor.withAlphaComponent(0.6)
            : hovering && isEnabled ? .white.withAlphaComponent(0.15) : nil
        layer?.backgroundColor = c?.cgColor
    }
}

@MainActor
final class SourceToolbar: NSObject {
    enum Action { case tool(AnnotationTool), undo, clear, color(NSColor), resize(AppDelegate.ResizeMode), stop }

    var onAction: ((Action) -> Void)?
    /// Window to follow; nil hides the toolbar
    var sourceWindowID: CGWindowID? {
        didSet { sourceWindowID == nil ? hide() : show() }
    }

    private var panel: OverlayPanel?
    private var timer: Timer?
    private var tool: AnnotationTool = .none
    private var color: NSColor = .systemRed

    private lazy var laser = ToolbarButton(symbol: "cursorarrow.rays", target: self, action: #selector(laserAction))
    private lazy var pen = ToolbarButton(symbol: "pencil.tip", target: self, action: #selector(penAction))
    private lazy var highlighter = ToolbarButton(symbol: "highlighter", target: self, action: #selector(highlighterAction))
    private lazy var colorButton = ToolbarButton(symbol: "circle.fill", target: self, action: #selector(colorAction(_:)))
    private lazy var undo = ToolbarButton(symbol: "arrow.uturn.backward", target: self, action: #selector(undoAction))
    private lazy var clear = ToolbarButton(symbol: "trash", target: self, action: #selector(clearAction))
    private lazy var resize = ToolbarButton(symbol: "arrow.up.left.and.arrow.down.right", target: self, action: #selector(resizeAction(_:)))
    private lazy var stop = ToolbarButton(symbol: "stop.circle.fill", target: self, action: #selector(stopAction))

    /// Syncs the buttons with the current annotation state
    func update(tool: AnnotationTool, color: NSColor) {
        self.tool = tool
        self.color = color
        guard panel != nil else { return }
        laser.isActive = tool == .laser
        pen.isActive = tool == .pen
        highlighter.isActive = tool == .highlighter
        colorButton.contentTintColor = color
        if sourceWindowID != nil { track() }
    }

    /// Re-applies the tooltips after a language change
    func updateTooltips() {
        laser.toolTip = L("Laser Pointer (⌃⌥L)", "激光笔（⌃⌥L）")
        pen.toolTip = L("Pen (⌃⌥D)", "画笔（⌃⌥D）")
        highlighter.toolTip = L("Highlighter (⌃⌥H)", "荧光笔（⌃⌥H）")
        colorButton.toolTip = L("Color", "颜色")
        undo.toolTip = L("Undo Last Stroke (⌃⌥Z)", "撤销上一笔（⌃⌥Z）")
        clear.toolTip = L("Clear All (⌃⌥C)", "清除全部（⌃⌥C）")
        resize.toolTip = L("Fit Source Window to Target", "按副屏调整源窗口")
        stop.toolTip = L("Stop Mirroring", "停止镜像")
    }

    // MARK: Internals

    private func show() {
        if panel == nil { build() }
        track()
        if timer == nil {
            let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.track() } }
            RunLoop.main.add(t, forMode: .common); timer = t
        }
    }

    private func hide() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil)
    }

    private func build() {
        let p = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.appearance = NSAppearance(named: .darkAqua)

        func separator() -> NSView {
            let b = NSBox()
            b.boxType = .separator
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 18).isActive = true
            return b
        }
        stop.contentTintColor = .systemRed
        let stack = NSStackView(views: [laser, pen, highlighter, colorButton, separator(),
                                        undo, clear, separator(), resize, stop])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.maskImage = Self.roundedMask(radius: 10)
        fx.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            stack.topAnchor.constraint(equalTo: fx.topAnchor),
            stack.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])
        p.contentView = fx
        p.setContentSize(stack.fittingSize)
        panel = p
        updateTooltips()
        update(tool: tool, color: color)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let d = radius * 2 + 1
        let img = NSImage(size: NSSize(width: d, height: d), flipped: false) { r in
            NSColor.black.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill(); return true }
        img.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        img.resizingMode = .stretch
        return img
    }

    /// Keeps the toolbar centered above the source window and ordered right above it
    private func track() {
        guard let wid = sourceWindowID, let panel, let f = onScreenFrame(of: wid)
        else { panel?.orderOut(nil); return }

        let size = panel.frame.size
        let screen = NSScreen.screens.max(by: {
            let a = $0.frame.intersection(f), b = $1.frame.intersection(f)
            return a.width * a.height < b.width * b.height
        })
        let vf = screen?.visibleFrame ?? f
        let x = min(max(f.midX - size.width / 2, vf.minX + 4), vf.maxX - size.width - 4)
        var y = f.maxY + 6
        if y + size.height > vf.maxY { y = f.maxY - size.height - 6 }   // No room above: inside the top edge
        let origin = NSPoint(x: x.rounded(), y: y.rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }

        // While annotating, stay above the overlay panel (.floating), which may cover the toolbar
        let level: NSWindow.Level = tool == .none ? .normal : NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        if panel.level != level { panel.level = level }
        if tool != .none {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if !isDirectlyAbove(wid) {
            panel.order(.above, relativeTo: Int(wid))
        }
    }

    private func isDirectlyAbove(_ wid: CGWindowID) -> Bool {
        guard let panel, panel.isVisible,
              let above = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], wid) as? [[String: Any]]
        else { return false }
        // Front-to-back order: the last normal-level window is the one right above the source
        let nearest = above.last { ($0[kCGWindowLayer as String] as? Int) == 0 }
        return (nearest?[kCGWindowNumber as String] as? Int) == panel.windowNumber
    }

    private func popUp(_ menu: NSMenu, under button: NSButton) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY + 4 : -4), in: button)
    }

    // MARK: Button actions

    @objc private func laserAction() { onAction?(.tool(.laser)) }
    @objc private func penAction() { onAction?(.tool(.pen)) }
    @objc private func highlighterAction() { onAction?(.tool(.highlighter)) }
    @objc private func undoAction() { onAction?(.undo) }
    @objc private func clearAction() { onAction?(.clear) }
    @objc private func stopAction() { onAction?(.stop) }

    @objc private func colorAction(_ sender: NSButton) {
        let m = NSMenu()
        for (i, (en, zh, c)) in AppDelegate.annotationColors.enumerated() {
            let it = NSMenuItem(title: L(en, zh), action: #selector(colorItemAction(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.state = color == c ? .on : .off
            it.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
                c.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill(); return true }
            m.addItem(it)
        }
        popUp(m, under: sender)
    }
    @objc private func colorItemAction(_ sender: NSMenuItem) {
        onAction?(.color(AppDelegate.annotationColors[sender.tag].2))
    }

    @objc private func resizeAction(_ sender: NSButton) {
        let m = NSMenu()
        let header = NSMenuItem(title: L("Fit Source Window to Target", "按副屏调整源窗口"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        m.addItem(header)
        for mode in AppDelegate.ResizeMode.allCases {
            let it = NSMenuItem(title: mode.title, action: #selector(resizeItemAction(_:)), keyEquivalent: mode.key)
            it.keyEquivalentModifierMask = [.control, .option]
            it.target = self
            it.tag = mode.rawValue
            m.addItem(it)
        }
        popUp(m, under: sender)
    }
    @objc private func resizeItemAction(_ sender: NSMenuItem) {
        if let mode = AppDelegate.ResizeMode(rawValue: sender.tag) { onAction?(.resize(mode)) }
    }
}
