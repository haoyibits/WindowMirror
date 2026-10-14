// WindowMirror — mirrors a window on the main screen to a secondary display in real time
// Requires macOS 14+ and ScreenCaptureKit

import AppKit
@preconcurrency import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreImage
import Carbon.HIToolbox

// MARK: - Utilities

/// UI language: follow the system (Chinese when the preferred system language is Chinese, otherwise English) / English / Chinese
enum AppLanguage: String, CaseIterable { case system, en, zh }

enum L10n {
    static var setting: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
    }
    static var isChinese: Bool {
        switch setting {
        case .en: return false
        case .zh: return true
        case .system: return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
        }
    }
}

/// Picks the English or Chinese string for the current language
func L(_ en: String, _ zh: String) -> String { L10n.isChinese ? zh : en }

enum FillMode: String, CaseIterable {
    case fit, fill, stretch, native
    var title: String {
        switch self {
        case .fit: return L("Fit (keep ratio, letterbox)", "适应（保持比例，留黑边）")
        case .fill: return L("Fill (keep ratio, crop edges)", "填充（保持比例，裁掉边缘）")
        case .stretch: return L("Stretch", "拉伸铺满")
        case .native: return L("Native pixels (1:1, no scaling, centered)", "原始像素（1:1，不缩放，居中）")
        }
    }
    var gravity: CALayerContentsGravity {
        switch self {
        case .fit: return .resizeAspect
        case .fill: return .resizeAspectFill
        case .stretch: return .resize
        case .native: return .center
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Frame of a window in Cocoa global coordinates (bottom-left origin); nil when it isn't on screen
func onScreenFrame(of wid: CGWindowID) -> CGRect? {
    guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as? [[String: Any]])?.first,
          (info[kCGWindowIsOnscreen as String] as? Bool) == true,
          let bd = info[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: bd as CFDictionary)
    else { return nil }
    let h = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
}

let debugLog = ProcessInfo.processInfo.environment["WM_DEBUG"] != nil
func dlog(_ s: @autoclosure () -> String) { if debugLog { FileHandle.standardError.write((s() + "\n").data(using: .utf8)!) } }

// MARK: - Mirror view and window

final class MirrorView: NSView {
    private let imageLayer = CALayer()
    let annotationLayer = AnnotationLayer()
    private var sourcePixelSize: CGSize = .zero

    var gravity: CALayerContentsGravity = .resizeAspect {
        didSet { imageLayer.contentsGravity = gravity; annotationLayer.setNeedsDisplay() }
    }

    /// Area where the source image is actually shown in this view (view coordinates)
    func displayedContentRect() -> CGRect {
        let b = bounds, sp = sourcePixelSize
        guard sp.width > 0, sp.height > 0 else { return b }
        let k = window?.backingScaleFactor ?? 2
        let size: CGSize
        switch gravity {
        case .resize: return b
        case .center: size = CGSize(width: sp.width / k, height: sp.height / k)
        case .resizeAspectFill:
            let s = max(b.width / sp.width, b.height / sp.height); size = CGSize(width: sp.width * s, height: sp.height * s)
        default:
            let s = min(b.width / sp.width, b.height / sp.height); size = CGSize(width: sp.width * s, height: sp.height * s)
        }
        return CGRect(x: b.midX - size.width / 2, y: b.midY - size.height / 2, width: size.width, height: size.height)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        wantsLayer = true
        imageLayer.contentsGravity = gravity
        imageLayer.frame = root.bounds
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        root.addSublayer(imageLayer)
        annotationLayer.frame = root.bounds
        annotationLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        annotationLayer.rectProvider = { [weak self] in self?.displayedContentRect() ?? .zero }
        root.addSublayer(annotationLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        annotationLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        annotationLayer.contentsScale = window?.backingScaleFactor ?? 2
        annotationLayer.setNeedsDisplay()
    }

    /// Pixel size of the view on its current screen
    var pixelSize: CGSize {
        let k = window?.backingScaleFactor ?? 2
        return CGSize(width: bounds.width * k, height: bounds.height * k)
    }

    func show(_ surface: IOSurface, crop: CGRect) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.contents = surface
        imageLayer.contentsRect = crop
        CATransaction.commit()
        let sp = CGSize(width: (CGFloat(IOSurfaceGetWidth(surface)) * crop.width).rounded(),
                        height: (CGFloat(IOSurfaceGetHeight(surface)) * crop.height).rounded())
        if sp != sourcePixelSize { sourcePixelSize = sp; annotationLayer.setNeedsDisplay() }
    }

    func clear() { imageLayer.contents = nil }

    var hdr: Bool = false {
        didSet { imageLayer.wantsExtendedDynamicRangeContent = hdr }
    }
}

final class MirrorWindow: NSWindow {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

// MARK: - Capture engine

final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "WindowMirror.capture", qos: .userInteractive)
    // The state below is only accessed on `queue`
    private var stream: SCStream?
    private var config: SCStreamConfiguration?
    private var resizing = false

    /// Per-frame callback (on a background queue): the frame surface and the normalized crop rect to show
    var onFrame: ((IOSurface, CGRect) -> Void)?
    /// The stream was stopped by the system (e.g. the source window was closed)
    var onStop: ((Error?) -> Void)?

    func start(filter: SCContentFilter, showsCursor: Bool, hdr: Bool) async throws {
        do {
            try await startStream(filter: filter, showsCursor: showsCursor, hdr: hdr)
        } catch where hdr {
            dlog("HDR start failed (\(error)), falling back to SDR")
            try await startStream(filter: filter, showsCursor: showsCursor, hdr: false)
        }
    }

    private func startStream(filter: SCContentFilter, showsCursor: Bool, hdr: Bool) async throws {
        await stop()
        let scale = CGFloat(filter.pointPixelScale)
        let rect = filter.contentRect
        let c = SCStreamConfiguration()
        c.width = max(16, Int((rect.width * scale).rounded()))
        c.height = max(16, Int((rect.height * scale).rounded()))
        c.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        c.queueDepth = 5
        if hdr, #available(macOS 15.0, *) {
            // HDR: half float + extended P3 keeps highlights above SDR white, captured as it looks on the source display
            c.captureDynamicRange = .hdrLocalDisplay
            c.pixelFormat = kCVPixelFormatType_64RGBAHalf
            c.colorSpaceName = CGColorSpace.extendedDisplayP3
        } else {
            c.pixelFormat = kCVPixelFormatType_32BGRA
            c.colorSpaceName = CGColorSpace.displayP3   // Wide-gamut capture so colors aren't squeezed into sRGB
        }
        c.showsCursor = showsCursor
        c.ignoreShadowsSingleWindow = true
        dlog("start: contentRect=\(rect) scale=\(scale) -> \(c.width)x\(c.height)")

        let s = SCStream(filter: filter, configuration: c, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        queue.sync {
            self.stream = s; self.config = c; self.resizing = false
            self.hdrActive = c.pixelFormat == kCVPixelFormatType_64RGBAHalf; self.loggedColor = false
        }
    }

    func stop() async {
        let s: SCStream? = queue.sync {
            let s = stream
            stream = nil; config = nil
            return s
        }
        if let s { try? await s.stopCapture() }
    }

    private let p3PropertyList: CFPropertyList? = CGColorSpace(name: CGColorSpace.displayP3)?.copyPropertyList()
    private let extP3PropertyList: CFPropertyList? = CGColorSpace(name: CGColorSpace.extendedDisplayP3)?.copyPropertyList()
    private var loggedColor = false
    private var hdrActive = false

    /// Whether the current stream is HDR
    var isHDR: Bool { queue.sync { stream != nil && hdrActive } }

    /// Current output resolution (pixels)
    var outputPixelSize: CGSize {
        queue.sync { config.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    }

    func setShowsCursor(_ on: Bool) {
        queue.async {
            guard let s = self.stream, let c = self.config else { return }
            c.showsCursor = on
            s.updateConfiguration(c) { _ in }
        }
    }

    // SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, stream === self.stream, sb.isValid,
              let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = arr.first,
              let raw = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw), status == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb),
              let surface = CVPixelBufferGetIOSurface(pb)?.takeUnretainedValue()
        else { return }

        let bufW = CGFloat(CVPixelBufferGetWidth(pb))
        let bufH = CGFloat(CVPixelBufferGetHeight(pb))
        var crop = CGRect(x: 0, y: 0, width: 1, height: 1)

        if let d = info[.contentRect] as? NSDictionary,
           let cr = CGRect(dictionaryRepresentation: d as CFDictionary),
           let cs = info[.contentScale] as? CGFloat, cs > 0,
           let sf = info[.scaleFactor] as? CGFloat, sf > 0 {
            // contentRect is in points: convert it to pixels to get the valid region of the buffer
            let px = CGRect(x: cr.minX * sf, y: cr.minY * sf, width: cr.width * sf, height: cr.height * sf)
            if bufW > 0, bufH > 0 {
                crop = CGRect(x: px.minX / bufW, y: px.minY / bufH,
                              width: min(1, px.width / bufW), height: min(1, px.height / bufH))
            }
            // When the source window is resized, adjust the output resolution to keep it sharp
            let wantW = Int((cr.width / cs * sf).rounded())
            let wantH = Int((cr.height / cs * sf).rounded())
            if let c = config, !resizing, wantW >= 16, wantH >= 16,
               abs(wantW - c.width) > 2 || abs(wantH - c.height) > 2 {
                dlog("resize: buf=\(Int(bufW))x\(Int(bufH)) cr=\(cr) cs=\(cs) sf=\(sf) -> \(wantW)x\(wantH)")
                resizing = true
                c.width = wantW; c.height = wantH
                stream.updateConfiguration(c) { [weak self] _ in
                    self?.queue.async { self?.resizing = false }
                }
            }
        }
        // Make sure the surface is tagged with a color space so Core Animation converts it correctly for the target display
        if !loggedColor {
            loggedColor = true
            dlog("color: hdr=\(hdrActive) fmt=\(CVPixelBufferGetPixelFormatType(pb)) surface tag=\(String(describing: IOSurfaceCopyValue(surface, kIOSurfaceColorSpace))) " +
                 "cv=\(String(describing: CVBufferCopyAttachment(pb, kCVImageBufferCGColorSpaceKey, nil)))")
        }
        if IOSurfaceCopyValue(surface, kIOSurfaceColorSpace) == nil, let pl = hdrActive ? extP3PropertyList : p3PropertyList {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, pl)
        }
        onFrame?(surface, crop)
    }

    // SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async {
            guard stream === self.stream else { return }
            self.stream = nil; self.config = nil
            self.onStop?(error)
        }
    }
}

// MARK: - App (menu bar)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate, SCContentSharingPickerObserver {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let windowListMenu = NSMenu()
    private let engine = CaptureEngine()
    private let mirrorView = MirrorView(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
    private var mirrorWindow: MirrorWindow?
    private var mirroringTitle: String?
    private var lastFilter: SCContentFilter?
    private let annotations = AnnotationController()
    private let toolbar = SourceToolbar()
    private var sourceWindowID: CGWindowID?
    private var sourcePID: pid_t?

    private let defaults = UserDefaults.standard
    private var fillMode: FillMode {
        get { FillMode(rawValue: defaults.string(forKey: "fillMode") ?? "") ?? .fit }
        set { defaults.set(newValue.rawValue, forKey: "fillMode"); mirrorView.gravity = newValue.gravity }
    }
    private var showsCursor: Bool {
        get { defaults.object(forKey: "showsCursor") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showsCursor"); engine.setShowsCursor(newValue && annotations.tool != .laser) }
    }
    private var showsToolbar: Bool {
        get { defaults.object(forKey: "showToolbar") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showToolbar"); toolbar.sourceWindowID = newValue ? sourceWindowID : nil }
    }
    private var hdrEnabled: Bool {
        get { defaults.object(forKey: "hdr") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hdr") }
    }
    /// Target display chosen by the user; nil means automatic (the first non-main display)
    private var targetDisplayID: CGDirectDisplayID? {
        get { (defaults.object(forKey: "targetDisplay") as? NSNumber)?.uint32Value }
        set { defaults.set(newValue.map { NSNumber(value: $0) }, forKey: "targetDisplay") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        menu.delegate = self
        windowListMenu.delegate = self
        statusItem.menu = menu
        mirrorView.gravity = fillMode.gravity

        engine.onFrame = { [weak self] surface, crop in
            DispatchQueue.main.async { self?.mirrorView.show(surface, crop: crop) }
        }
        engine.onStop = { [weak self] error in
            DispatchQueue.main.async {
                dlog("stream stopped: \(String(describing: error))")
                self?.stopMirroring()
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }

        SCContentSharingPicker.shared.add(self)
        setupAnnotations()
        dlog("launch: screen capture access = \(CGPreflightScreenCaptureAccess())")
        runDebugHooks()
    }

    private func dumpMenu(_ m: NSMenu, indent: Int) {
        for it in m.items {
            if it.isSeparatorItem { print(String(repeating: "  ", count: indent) + "----"); continue }
            var key = ""
            if !it.keyEquivalent.isEmpty {
                key = it.keyEquivalentModifierMask.contains(.control) ? "  [⌃⌥\(it.keyEquivalent.uppercased())]" : "  [⌘\(it.keyEquivalent.uppercased())]"
            }
            print(String(repeating: "  ", count: indent) + (it.state == .on ? "✓ " : "") + it.title + key)
            if let sub = it.submenu {
                if sub === windowListMenu { rebuildWindowList() }
                dumpMenu(sub, indent: indent + 1)
            }
        }
    }

    /// Debug only: WM_AUTOSTART=<app name fragment> mirrors that app's first window on the main screen;
    /// WM_SNAPSHOT=<path.png> saves the 30th raw frame as an image
    private func runDebugHooks() {
        let env = ProcessInfo.processInfo.environment
        if env["WM_DUMPMENU"] != nil {
            let saved = L10n.setting
            L10n.setting = .system
            print("system languages:", Locale.preferredLanguages.prefix(2), "-> chinese:", L10n.isChinese)
            for lang in [AppLanguage.en, .zh] {
                L10n.setting = lang
                rebuildMainMenu()
                rebuildWindowList()
                print("=== \(lang.rawValue) ===")
                dumpMenu(menu, indent: 0)
            }
            L10n.setting = saved
            print("tooltip:", statusItem.button?.toolTip ?? "-")
            exit(0)
        }
        if let path = env["WM_SNAPSHOT"] {
            var n = 0
            let show = engine.onFrame
            engine.onFrame = { surface, crop in
                n += 1
                if n == 30 {
                    let img = CIImage(ioSurface: surface)
                    let ctx = CIContext()
                    try? ctx.writePNGRepresentation(of: img, to: URL(fileURLWithPath: path),
                                                    format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                    dlog("snapshot: surface=\(IOSurfaceGetWidth(surface))x\(IOSurfaceGetHeight(surface)) crop=\(crop) -> \(path)")
                }
                show?(surface, crop)
            }
        }
        guard let name = env["WM_AUTOSTART"]?.lowercased() else { return }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let main = CGDisplayBounds(CGMainDisplayID())
                guard let w = content.windows.first(where: {
                    $0.windowLayer == 0 && $0.frame.width > 200 && $0.frame.intersects(main) &&
                    ($0.owningApplication?.applicationName.lowercased().contains(name) ?? false)
                }) else { dlog("autostart: no window for \(name)"); return }
                dlog("autostart: \(w.owningApplication?.applicationName ?? "") '\(w.title ?? "")' frame=\(w.frame)")
                startMirroring(filter: SCContentFilter(desktopIndependentWindow: w),
                               title: w.owningApplication?.applicationName ?? name, window: w)
                if env["WM_AUTOMATCH"] != nil {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    resizeSource(ResizeMode(rawValue: Int(env["WM_AUTOMATCH"] ?? "") ?? 0) ?? .native)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    dlog("after match: output=\(engine.outputPixelSize) target=\(mirrorView.pixelSize) hdr=\(engine.isHDR)")
                }
                if let dir = env["WM_TESTDRAW"] {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    annotations.setTool(.pen)
                    let circle = (0...40).map { i -> CGPoint in
                        let a = Double(i) / 40 * 2 * .pi
                        return CGPoint(x: 0.5 + 0.2 * cos(a), y: 0.5 + 0.25 * sin(a))
                    }
                    annotations.debugStroke(circle)
                    annotations.setTool(.highlighter)
                    annotations.debugStroke([CGPoint(x: 0.1, y: 0.15), CGPoint(x: 0.6, y: 0.15)])
                    annotations.setTool(.laser)
                    annotations.debugLaser(CGPoint(x: 0.8, y: 0.8))
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await debugCaptureOwnWindows(dir: dir)
                    annotations.setTool(.none)
                }
            } catch {
                dlog("autostart error: \(error)")
            }
        }
    }

    // MARK: Menu

    private func updateStatusIcon() {
        let name = mirroringTitle == nil ? "rectangle.on.rectangle" : "rectangle.fill.on.rectangle.fill"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "WindowMirror")
        statusItem.button?.toolTip = mirroringTitle.map { L("Mirroring: \($0)", "正在镜像：\($0)") } ?? L("WindowMirror", "窗口镜像")
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        if m === menu { rebuildMainMenu() } else if m === windowListMenu { rebuildWindowList() }
    }

    private func rebuildMainMenu() {
        menu.removeAllItems()

        let state = NSMenuItem(title: mirroringTitle.map { L("Mirroring: \($0)", "正在镜像：\($0)") } ?? L("Not mirroring", "未在镜像"), action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())

        menu.addItem(item(L("Pick Window…", "点选窗口…"), #selector(pickWithSystemPicker), key: "p"))
        let listItem = NSMenuItem(title: L("Choose from Main-Screen Windows", "从主屏窗口列表选择"), action: nil, keyEquivalent: "")
        listItem.submenu = windowListMenu
        menu.addItem(listItem)
        menu.addItem(.separator())

        // Annotation
        let annMenu = NSMenu()
        let canAnnotate = annotations.sourceWindowID != nil
        func toolItem(_ title: String, _ t: AnnotationTool, _ key: String) -> NSMenuItem {
            let it = item(title, #selector(annotationToolAction(_:)), key: key)
            it.keyEquivalentModifierMask = [.control, .option]
            it.representedObject = t == .laser ? "laser" : t == .pen ? "pen" : "highlighter"
            it.state = annotations.tool == t ? .on : .off
            it.isEnabled = canAnnotate
            return it
        }
        annMenu.addItem(toolItem(L("Laser Pointer", "激光笔"), .laser, "l"))
        annMenu.addItem(toolItem(L("Pen", "画笔"), .pen, "d"))
        annMenu.addItem(toolItem(L("Highlighter", "荧光笔"), .highlighter, "h"))
        let exitAnn = item(L("Exit Annotation", "退出标注"), #selector(exitAnnotation), key: "x")
        exitAnn.keyEquivalentModifierMask = [.control, .option]
        exitAnn.isEnabled = annotations.tool != .none
        annMenu.addItem(exitAnn)
        annMenu.addItem(.separator())
        let undo = item(L("Undo Last Stroke", "撤销上一笔"), #selector(undoStroke), key: "z")
        undo.keyEquivalentModifierMask = [.control, .option]
        annMenu.addItem(undo)
        let clr = item(L("Clear All", "清除全部"), #selector(clearStrokes), key: "c")
        clr.keyEquivalentModifierMask = [.control, .option]
        annMenu.addItem(clr)
        annMenu.addItem(.separator())
        let colorMenu = NSMenu()
        for (i, (en, zh, c)) in Self.annotationColors.enumerated() {
            let it = item(L(en, zh), #selector(selectAnnotationColor(_:)))
            it.tag = i
            it.state = annotations.model.color == c ? .on : .off
            let sw = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
                c.setFill(); NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill(); return true }
            it.image = sw
            colorMenu.addItem(it)
        }
        let colorItem = NSMenuItem(title: L("Color", "颜色"), action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        annMenu.addItem(colorItem)
        let fade = item(L("Fade Strokes After a Few Seconds", "笔迹几秒后自动消失"), #selector(toggleAutoFade))
        fade.state = annotations.model.autoFade ? .on : .off
        annMenu.addItem(fade)
        let tb = item(L("Show Toolbar Above Source Window", "在源窗口上方显示工具栏"), #selector(toggleToolbar))
        tb.state = showsToolbar ? .on : .off
        annMenu.addItem(tb)
        let annItem = NSMenuItem(title: canAnnotate ? L("Annotate", "标注") : L("Annotate (start mirroring first)", "标注（先开始镜像）"), action: nil, keyEquivalent: "")
        annItem.submenu = annMenu
        menu.addItem(annItem)
        menu.addItem(.separator())

        // Target display
        let screenMenu = NSMenu()
        let auto = item(L("Automatic (first secondary display)", "自动（第一块副屏）"), #selector(selectTargetScreen(_:)))
        auto.tag = 0
        auto.state = targetDisplayID == nil ? .on : .off
        screenMenu.addItem(auto)
        for s in NSScreen.screens {
            let isMain = s.displayID == CGMainDisplayID()
            let size = "\(Int(s.frame.width))×\(Int(s.frame.height))"
            let it = item("\(s.localizedName)  \(size)\(isMain ? L(" (main, windowed)", "（主屏，窗口模式）") : "")", #selector(selectTargetScreen(_:)))
            it.tag = Int(s.displayID)
            it.state = targetDisplayID == s.displayID ? .on : .off
            screenMenu.addItem(it)
        }
        let screenItem = NSMenuItem(title: L("Target Display: \(targetScreen().localizedName)", "目标显示器：\(targetScreen().localizedName)"), action: nil, keyEquivalent: "")
        screenItem.submenu = screenMenu
        menu.addItem(screenItem)

        // Scaling
        let fillMenu = NSMenu()
        for (i, f) in FillMode.allCases.enumerated() {
            let it = item(f.title, #selector(selectFillMode(_:)))
            it.tag = i
            it.state = f == fillMode ? .on : .off
            fillMenu.addItem(it)
        }
        let fillItem = NSMenuItem(title: L("Scaling", "缩放方式"), action: nil, keyEquivalent: "")
        fillItem.submenu = fillMenu
        menu.addItem(fillItem)

        let cursor = item(L("Show Mouse Pointer", "显示鼠标指针"), #selector(toggleCursor))
        cursor.state = showsCursor ? .on : .off
        menu.addItem(cursor)
        let hdrItem = item(L("HDR (keep highlights, match source look)", "HDR（保留高光，按源屏观感）"), #selector(toggleHDR))
        hdrItem.state = hdrEnabled ? .on : .off
        menu.addItem(hdrItem)

        if mirroringTitle != nil {
            menu.addItem(.separator())
            let src = engine.outputPixelSize
            let dst = mirrorView.pixelSize
            if src.width > 0, dst.width > 0 {
                let k = min(dst.width / src.width, dst.height / src.height)
                let exact = abs(src.width - dst.width) <= 2 && abs(src.height - dst.height) <= 2
                let desc = exact ? L("pixel 1:1 ✓", "像素 1:1 ✓")
                    : String(format: k >= 1 ? L("upscaled %.2f× when fitted", "适应时放大 %.2f×") : L("downscaled %.2f× when fitted", "适应时缩小 %.2f×"), k)
                let info = NSMenuItem(title: L("Source \(Int(src.width))×\(Int(src.height)) → target \(Int(dst.width))×\(Int(dst.height)) px, \(desc)",
                                                   "源 \(Int(src.width))×\(Int(src.height)) → 目标 \(Int(dst.width))×\(Int(dst.height)) 像素，\(desc)"),
                                      action: nil, keyEquivalent: "")
                info.isEnabled = false
                menu.addItem(info)
            }
            let resizeMenu = NSMenu()
            for mode in ResizeMode.allCases {
                let it = item(mode.title, #selector(resizeSourceAction(_:)), key: mode.key)
                if !mode.key.isEmpty { it.keyEquivalentModifierMask = [.control, .option] }
                it.tag = mode.rawValue
                resizeMenu.addItem(it)
            }
            let resizeItem = NSMenuItem(title: L("Fit Source Window to Target", "按副屏调整源窗口"), action: nil, keyEquivalent: "")
            resizeItem.submenu = resizeMenu
            resizeItem.isEnabled = sourceWindowID != nil
            menu.addItem(resizeItem)
        }
        menu.addItem(.separator())

        let stop = item(L("Stop Mirroring", "停止镜像"), #selector(stopMirroringAction), key: "s")
        stop.isEnabled = mirroringTitle != nil
        menu.addItem(stop)
        let langMenu = NSMenu()
        for (lang, title) in [(AppLanguage.system, L("Follow System", "跟随系统")), (.en, "English"), (.zh, "简体中文")] {
            let it = item(title, #selector(selectLanguage(_:)))
            it.representedObject = lang.rawValue
            it.state = L10n.setting == lang ? .on : .off
            langMenu.addItem(it)
        }
        let langItem = NSMenuItem(title: "Language / 语言", action: nil, keyEquivalent: "")
        langItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        langItem.submenu = langMenu
        menu.addItem(langItem)
        menu.addItem(.separator())
        menu.addItem(item(L("Quit", "退出"), #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    /// Lists normal windows on the main screen via CGWindowList (the menu has to be filled synchronously)
    private func rebuildWindowList() {
        windowListMenu.removeAllItems()

        if !CGPreflightScreenCaptureAccess() {
            let it = item(L("Screen Recording permission needed — click to grant…", "需要“屏幕录制”权限，点此授权…"), #selector(requestPermission))
            windowListMenu.addItem(it)
            let hint = NSMenuItem(title: L("(Or use “Pick Window…”, which needs no permission)", "（或者用“点选窗口…”，无需授权）"), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            windowListMenu.addItem(hint)
            return
        }

        let mainBounds = CGDisplayBounds(CGMainDisplayID())
        let myPID = ProcessInfo.processInfo.processIdentifier
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        var count = 0
        for w in raw {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != myPID,
                  let num = w[kCGWindowNumber as String] as? UInt32,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  b.width >= 80, b.height >= 60,
                  b.intersects(mainBounds)
            else { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            let title = (w[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            var label = title.map { "\(owner) — \($0)" } ?? owner
            if label.count > 70 { label = String(label.prefix(68)) + "…" }

            let it = item(label, #selector(selectWindowFromList(_:)))
            it.tag = Int(num)
            it.representedObject = label
            if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
                icon.size = NSSize(width: 16, height: 16)
                it.image = icon
            }
            windowListMenu.addItem(it)
            count += 1
        }
        if count == 0 {
            let it = NSMenuItem(title: L("No windows to mirror on the main screen", "主屏上没有可镜像的窗口"), action: nil, keyEquivalent: "")
            it.isEnabled = false
            windowListMenu.addItem(it)
        }
    }

    // MARK: Actions

    @objc private func pickWithSystemPicker() {
        let picker = SCContentSharingPicker.shared
        var cfg = SCContentSharingPickerConfiguration()
        cfg.allowedPickerModes = [.singleWindow]
        if let bid = Bundle.main.bundleIdentifier { cfg.excludedBundleIDs = [bid] }
        picker.defaultConfiguration = cfg
        picker.isActive = true
        picker.present(using: .window)
    }

    @objc private func selectWindowFromList(_ sender: NSMenuItem) {
        let windowID = CGWindowID(sender.tag)
        let label = sender.representedObject as? String ?? L("Window", "窗口")
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let w = content.windows.first(where: { $0.windowID == windowID }) else {
                    showAlert(L("Window not found", "找不到这个窗口"), L("It may have been closed or minimized.", "它可能已经关闭或被最小化了。"))
                    return
                }
                startMirroring(filter: SCContentFilter(desktopIndependentWindow: w), title: label, window: w)
            } catch {
                showAlert(L("Couldn’t get the window list", "无法获取窗口列表"), error.localizedDescription)
            }
        }
    }

    @objc private func selectTargetScreen(_ sender: NSMenuItem) {
        targetDisplayID = sender.tag == 0 ? nil : CGDirectDisplayID(sender.tag)
        if mirroringTitle != nil { placeMirrorWindow() }
    }

    @objc private func selectFillMode(_ sender: NSMenuItem) {
        fillMode = FillMode.allCases[sender.tag]
    }

    @objc private func toggleCursor() { showsCursor.toggle() }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        L10n.setting = AppLanguage(rawValue: sender.representedObject as? String ?? "") ?? .system
        updateStatusIcon()
        toolbar.updateTooltips()
        if let w = mirrorWindow, w.styleMask.contains(.titled) {
            w.title = L("Mirror: \(mirroringTitle ?? "")", "镜像：\(mirroringTitle ?? "")")
        }
    }

    static let annotationColors: [(String, String, NSColor)] = [
        ("Red", "红", .systemRed), ("Yellow", "黄", .systemYellow), ("Green", "绿", .systemGreen),
        ("Blue", "蓝", .systemBlue), ("White", "白", .white),
    ]

    private func setupAnnotations() {
        annotations.model.autoFade = defaults.bool(forKey: "autoFade")
        annotations.mirrorLayer = mirrorView.annotationLayer
        mirrorView.annotationLayer.model = annotations.model
        annotations.onToolChange = { [weak self] t in
            guard let self else { return }
            // In laser mode, hide the system pointer in the mirror and show only the dot
            self.engine.setShowsCursor(self.showsCursor && t != .laser)
            self.updateStatusIcon()
            self.syncToolbar()
        }
        toolbar.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .tool(let t): self.annotations.toggle(t)
            case .undo: self.annotations.undo()
            case .clear: self.annotations.clear()
            case .color(let c): self.annotations.setColor(c); self.syncToolbar()
            case .resize(let mode): self.resizeSource(mode)
            case .stop: self.stopMirroring()
            }
        }
        let kc = { (k: Int) in k }
        HotKeys.register(1, keyCode: kc(kVK_ANSI_L)) { [weak self] in MainActor.assumeIsolated { self?.annotations.toggle(.laser) } }
        HotKeys.register(2, keyCode: kc(kVK_ANSI_D)) { [weak self] in MainActor.assumeIsolated { self?.annotations.toggle(.pen) } }
        HotKeys.register(3, keyCode: kc(kVK_ANSI_H)) { [weak self] in MainActor.assumeIsolated { self?.annotations.toggle(.highlighter) } }
        HotKeys.register(4, keyCode: kc(kVK_ANSI_X)) { [weak self] in MainActor.assumeIsolated { self?.annotations.setTool(.none) } }
        HotKeys.register(5, keyCode: kc(kVK_ANSI_Z)) { [weak self] in MainActor.assumeIsolated { self?.annotations.undo() } }
        HotKeys.register(6, keyCode: kc(kVK_ANSI_C)) { [weak self] in MainActor.assumeIsolated { self?.annotations.clear() } }
        HotKeys.register(7, keyCode: kc(kVK_ANSI_M)) { [weak self] in MainActor.assumeIsolated { self?.resizeSource(.native) } }
        HotKeys.register(8, keyCode: kc(kVK_ANSI_R)) { [weak self] in MainActor.assumeIsolated { self?.resizeSource(.largest) } }
    }

    @objc private func annotationToolAction(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "laser": annotations.toggle(.laser)
        case "pen": annotations.toggle(.pen)
        default: annotations.toggle(.highlighter)
        }
    }
    @objc private func exitAnnotation() { annotations.setTool(.none) }
    @objc private func undoStroke() { annotations.undo() }
    @objc private func clearStrokes() { annotations.clear() }
    @objc private func selectAnnotationColor(_ sender: NSMenuItem) {
        annotations.setColor(Self.annotationColors[sender.tag].2)
        syncToolbar()
    }
    @objc private func toggleToolbar() { showsToolbar.toggle() }

    private func syncToolbar() { toolbar.update(tool: annotations.tool, color: annotations.model.color) }
    @objc private func toggleAutoFade() {
        annotations.model.autoFade.toggle()
        defaults.set(annotations.model.autoFade, forKey: "autoFade")
    }

    @objc private func toggleHDR() {
        hdrEnabled.toggle()
        // If mirroring, restart with the same source
        if let f = lastFilter, let t = mirroringTitle {
            let wid = sourceWindowID, pid = sourcePID
            Task {
                do {
                    mirrorView.hdr = hdrEnabled
                    try await engine.start(filter: f, showsCursor: showsCursor, hdr: hdrEnabled)
                    mirrorView.hdr = engine.isHDR
                    sourceWindowID = wid; sourcePID = pid; mirroringTitle = t
                } catch {
                    stopMirroring()
                    showAlert(L("Couldn’t switch HDR", "切换 HDR 失败"), error.localizedDescription)
                }
            }
        }
    }

    @objc private func stopMirroringAction() { stopMirroring() }

    @objc private func quit() {
        Task {
            await engine.stop()
            NSApp.terminate(nil)
        }
    }

    @objc private func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            showAlert(L("Please grant Screen Recording permission", "请授予“屏幕录制”权限"),
                      L("Turn on WindowMirror in System Settings › Privacy & Security › Screen & System Audio Recording, then reopen the app.",
                        "在“系统设置 › 隐私与安全性 › 屏幕与系统录音”中勾选 WindowMirror，然后重新打开本工具。"))
        }
    }

    // MARK: Mirroring

    private func startMirroring(filter: SCContentFilter, title: String, window: SCWindow?) {
        mirroringTitle = title
        sourceWindowID = window?.windowID
        sourcePID = window?.owningApplication?.processID
        annotations.setTool(.none)
        annotations.sourceWindowID = window?.windowID
        toolbar.sourceWindowID = showsToolbar ? window?.windowID : nil
        syncToolbar()
        lastFilter = filter
        updateStatusIcon()
        mirrorView.clear()
        placeMirrorWindow()
        Task {
            do {
                mirrorView.hdr = hdrEnabled
                try await engine.start(filter: filter, showsCursor: showsCursor, hdr: hdrEnabled)
                mirrorView.hdr = engine.isHDR
            } catch {
                stopMirroring()
                showAlert(L("Couldn’t start mirroring", "开始镜像失败"), error.localizedDescription)
            }
        }
    }

    private func stopMirroring() {
        annotations.setTool(.none)
        annotations.sourceWindowID = nil
        toolbar.sourceWindowID = nil
        mirroringTitle = nil
        sourceWindowID = nil
        sourcePID = nil
        lastFilter = nil
        updateStatusIcon()
        Task { await engine.stop() }
        mirrorView.clear()
        mirrorWindow?.delegate = nil
        mirrorWindow?.orderOut(nil)
        mirrorWindow = nil
    }

    private func targetScreen() -> NSScreen {
        let screens = NSScreen.screens
        if let id = targetDisplayID, let s = screens.first(where: { $0.displayID == id }) { return s }
        let main = CGMainDisplayID()
        return screens.first(where: { $0.displayID != main }) ?? screens.first ?? NSScreen.main!
    }

    /// Secondary display target: borderless, covering the whole screen; main display target (e.g. only one screen): a normal resizable window
    private func placeMirrorWindow() {
        let screen = targetScreen()
        let fullscreen = screen.displayID != CGMainDisplayID()

        mirrorWindow?.delegate = nil
        mirrorWindow?.orderOut(nil)

        let win: MirrorWindow
        if fullscreen {
            win = MirrorWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.level = .statusBar
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            win.hasShadow = false
            win.setFrame(screen.frame, display: true)
        } else {
            let vf = screen.visibleFrame
            let size = NSSize(width: min(960, vf.width * 0.6), height: min(600, vf.height * 0.6))
            let rect = NSRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height)
            win = MirrorWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
            win.title = L("Mirror: \(mirroringTitle ?? "")", "镜像：\(mirroringTitle ?? "")")
            win.delegate = self
        }
        win.isReleasedWhenClosed = false
        win.backgroundColor = .black
        win.contentView = mirrorView
        mirrorView.viewDidChangeBackingProperties()
        win.onEscape = { [weak self] in self?.stopMirroring() }
        mirrorWindow = win

        if fullscreen {
            win.orderFrontRegardless()      // Don't steal focus on the main screen
        } else {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func screensChanged() {
        dlog("screens changed: \(NSScreen.screens.map { $0.localizedName })")
        if mirroringTitle != nil { placeMirrorWindow() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        stopMirroring()
        return false
    }

    private func debugCaptureOwnWindows(dir: String) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mine = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            for (i, w) in mine.enumerated() {
                let cfg = SCStreamConfiguration()
                cfg.width = Int(w.frame.width * 2); cfg.height = Int(w.frame.height * 2)
                let img = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg)
                let url = URL(fileURLWithPath: dir).appendingPathComponent("own_\(i)_\(Int(w.frame.width))x\(Int(w.frame.height)).png")
                if let d = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) { try d.write(to: url) }
                dlog("captured own window \(w.windowID) frame=\(w.frame) -> \(url.lastPathComponent)")
            }
        } catch { dlog("debug capture error: \(error)") }
    }

    // MARK: Matching the source window size

    enum ResizeMode: Int, CaseIterable {
        case native = 0, largest, keepWidth, keepHeight
        var title: String {
            switch self {
            case .native: return L("Pixel 1:1 (same size as target)", "像素 1:1（与副屏同尺寸）")
            case .largest: return L("Same Ratio, Largest", "同比例，尽量大")
            case .keepWidth: return L("Same Ratio, Keep Width", "同比例，保持当前宽度")
            case .keepHeight: return L("Same Ratio, Keep Height", "同比例，保持当前高度")
            }
        }
        /// Global hotkey letter (with ⌃⌥), if any
        var key: String {
            switch self {
            case .native: return "m"
            case .largest: return "r"
            default: return ""
            }
        }
    }

    @objc private func resizeSourceAction(_ sender: NSMenuItem) {
        resizeSource(ResizeMode(rawValue: sender.tag) ?? .largest)
    }

    @objc private func matchSourceToTarget() { resizeSource(.native) }

    /// Resizes the source window to the pixel size or aspect ratio of the target (the mirror view)
    private func resizeSource(_ mode: ResizeMode) {
        guard let wid = sourceWindowID, let pid = sourcePID, mirrorWindow != nil else { NSSound.beep(); return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            showAlert(L("Accessibility permission needed", "需要“辅助功能”权限"),
                      L("Resizing another app’s window needs this permission. Turn on WindowMirror in System Settings › Privacy & Security › Accessibility, then try again.",
                        "调整其他应用的窗口大小需要此权限。请在“系统设置 › 隐私与安全性 › 辅助功能”中打开 WindowMirror，然后再试一次。"))
            return
        }
        let targetPx = mirrorView.pixelSize
        guard targetPx.width > 0, targetPx.height > 0 else { return }
        let aspect = targetPx.width / targetPx.height
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let w = content.windows.first(where: { $0.windowID == wid }) else {
                    showAlert(L("Source window not found", "找不到源窗口"), L("It may have been closed.", "它可能已经关闭。")); return
                }
                // Display the source window is on (largest overlap) and its visible area (CG coordinates, top-left origin)
                let disp = content.displays.max(by: {
                    let a = $0.frame.intersection(w.frame), b = $1.frame.intersection(w.frame)
                    return a.width * a.height < b.width * b.height
                })
                let srcScreen = NSScreen.screens.first(where: { $0.displayID == disp?.displayID })
                let srcScale = srcScreen?.backingScaleFactor ?? 2
                let h0 = NSScreen.screens.first?.frame.height ?? 0
                let vf: CGRect = srcScreen.map {
                    CGRect(x: $0.visibleFrame.minX, y: h0 - $0.visibleFrame.maxY, width: $0.visibleFrame.width, height: $0.visibleFrame.height)
                } ?? disp?.frame ?? w.frame

                var want: CGSize
                switch mode {
                case .native: want = CGSize(width: targetPx.width / srcScale, height: targetPx.height / srcScale)
                case .largest:
                    want = vf.width / vf.height > aspect ? CGSize(width: vf.height * aspect, height: vf.height)
                                                         : CGSize(width: vf.width, height: vf.width / aspect)
                case .keepWidth: want = CGSize(width: w.frame.width, height: w.frame.width / aspect)
                case .keepHeight: want = CGSize(width: w.frame.height * aspect, height: w.frame.height)
                }
                // Scale down proportionally if it doesn't fit
                var clamped = false
                if want.width > vf.width + 0.5 || want.height > vf.height + 0.5 {
                    let k = min(vf.width / want.width, vf.height / want.height)
                    want = CGSize(width: want.width * k, height: want.height * k)
                    clamped = true
                }
                want = CGSize(width: want.width.rounded(.down), height: want.height.rounded(.down))
                // Keep the position if possible; only move it back when it goes past the visible area
                var origin = w.frame.origin
                origin.x = min(max(origin.x, vf.minX), vf.maxX - want.width)
                origin.y = min(max(origin.y, vf.minY), vf.maxY - want.height)

                guard let ax = Self.findAXWindow(pid: pid, frame: w.frame) else {
                    showAlert(L("Can’t control this window", "无法控制这个窗口"), L("The app doesn’t expose this window through Accessibility.", "该应用没有通过辅助功能暴露这个窗口。")); return
                }
                Self.axSet(ax, kAXPositionAttribute, origin)
                Self.axSet(ax, kAXSizeAttribute, want)
                Self.axSet(ax, kAXPositionAttribute, origin)   // Some apps re-constrain the position after a size change
                try? await Task.sleep(nanoseconds: 300_000_000)
                let got = Self.axSize(ax) ?? .zero
                dlog("resize \(mode): target=\(targetPx) aspect=\(aspect) vf=\(vf) want=\(want) got=\(got)")

                guard got.width > 0, got.height > 0 else { return }
                let gotAspect = got.width / got.height
                let k = min(targetPx.width / (got.width * srcScale), targetPx.height / (got.height * srcScale))
                if abs(gotAspect - aspect) / aspect > 0.01 {
                    showAlert(L("Couldn’t match the ratio exactly", "比例没能完全匹配"),
                              L("Target \(Int(want.width))×\(Int(want.height)) pt, actual window \(Int(got.width))×\(Int(got.height)) pt. " +
                                "The app may limit its window size, or resize in fixed steps (for example, terminals resize by rows and columns).",
                                "目标 \(Int(want.width))×\(Int(want.height)) 点，窗口实际为 \(Int(got.width))×\(Int(got.height)) 点。" +
                                "该应用可能限制了窗口的最小或最大尺寸，或者按固定步长调整大小（例如终端按字符行列）。"))
                } else if mode == .native && clamped {
                    showAlert(L("The 1:1 size doesn’t fit on the main screen", "主屏放不下 1:1 尺寸"),
                              L("Scaled down to \(Int(got.width))×\(Int(got.height)) pt at the target’s aspect ratio. The mirror fills the target screen but is upscaled \(String(format: "%.2f", k))×.",
                                "已按副屏比例缩小到 \(Int(got.width))×\(Int(got.height)) 点，副屏会铺满，但画面会放大 \(String(format: "%.2f", k)) 倍。"))
                }
            } catch {
                showAlert(L("Resize failed", "调整失败"), error.localizedDescription)
            }
        }
    }

    private static func findAXWindow(pid: pid_t, frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
              let wins = v as? [AXUIElement] else { return nil }
        return wins.min(by: { score($0, frame) < score($1, frame) })
    }
    private static func score(_ e: AXUIElement, _ f: CGRect) -> CGFloat {
        guard let p = axPoint(e), let s = axSize(e) else { return .greatestFiniteMagnitude }
        return abs(p.x - f.minX) + abs(p.y - f.minY) + abs(s.width - f.width) + abs(s.height - f.height)
    }
    private static func axPoint(_ e: AXUIElement) -> CGPoint? {
        var v: CFTypeRef?; var p = CGPoint.zero
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &v) == .success, let v,
              AXValueGetValue(v as! AXValue, .cgPoint, &p) else { return nil }
        return p
    }
    private static func axSize(_ e: AXUIElement) -> CGSize? {
        var v: CFTypeRef?; var s = CGSize.zero
        guard AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &v) == .success, let v,
              AXValueGetValue(v as! AXValue, .cgSize, &s) else { return nil }
        return s
    }
    private static func axSet(_ e: AXUIElement, _ attr: String, _ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(e, attr as CFString, v) }
    }
    private static func axSet(_ e: AXUIElement, _ attr: String, _ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(e, attr as CFString, v) }
    }

    // MARK: SCContentSharingPickerObserver

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                picker.isActive = false
                var title = L("Selected window", "所选窗口")
                var window: SCWindow?
                if #available(macOS 15.2, *), let w = filter.includedWindows.first {
                    window = w
                    let app = w.owningApplication?.applicationName ?? ""
                    let t = w.title ?? ""
                    title = [app, t].filter { !$0.isEmpty }.joined(separator: " — ")
                }
                self.startMirroring(filter: filter, title: title, window: window)
            }
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async { picker.isActive = false }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.showAlert(L("Couldn’t open the window picker", "无法打开窗口选择器"), error.localizedDescription) }
        }
    }

    // MARK: Misc

    private func showAlert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
