import AppKit

@MainActor
struct DockIdleCatArtwork {
    static let shared = DockIdleCatArtwork()
    let base: NSImage?
    let pupils: [NSImage]
    let eyeMask: CGImage?

    var isComplete: Bool { base != nil && pupils.count == 2 && eyeMask != nil }

    init() {
        func load(_ name: String) -> NSImage? {
            guard let folder = AppResources.directory("DockIdleCat"),
                  let image = NSImage(contentsOf: folder.appendingPathComponent(name)), image.isValid else { return nil }
            image.isTemplate = false
            return image
        }
        base = load("CatIdleBase.png")
        pupils = ["CatPupilLeft.png", "CatPupilRight.png"].compactMap(load)
        eyeMask = load("CatEyesMask.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    func draw(in rect: NSRect, direction: CGVector) {
        guard isComplete, let base, let eyeMask,
              let context = NSGraphicsContext.current?.cgContext else {
            AppResources.dockIdleCat?.draw(in: rect)
            return
        }
        base.draw(in: rect)
        context.saveGState()
        context.interpolationQuality = .high
        context.clip(to: rect, mask: eyeMask)
        // Both eyes share a direction; the fixed aperture keeps every moved pixel inside the eyes.
        let offset = rect.offsetBy(dx: direction.dx * rect.width * 0.020,
                                   dy: direction.dy * rect.height * 0.016)
        for pupil in pupils { pupil.draw(in: offset) }
        context.restoreGState()
    }
}

@MainActor
final class DockIdleCatView: NSView {
    var followsMouse = false { didSet { updateTracking() } }
    private(set) var gaze = CatGaze()
    private var timer: Timer?
    private var lastTime = ProcessInfo.processInfo.systemUptime
    var isTracking: Bool { timer != nil }
    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.name = "dock-idle-cat"
        layer?.backgroundColor = NSColor.clear.cgColor
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(updateTracking),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(updateTracking), name: name, object: nil)
        }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(updateTracking),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        updateTracking()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc private func updateTracking() {
        let visible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        guard followsMouse, visible, !isHiddenOrHasHiddenAncestor,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              DockIdleCatArtwork.shared.isComplete else {
            let wasMoving = timer != nil || gaze.direction != .zero
            timer?.invalidate()
            timer = nil
            gaze.reset()
            if wasMoving { needsDisplay = true }
            return
        }
        guard timer == nil else { return }
        lastTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            MainActor.assumeIsolated { self.tick() }
        }
        timer.tolerance = 0.003
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var artworkRect: NSRect {
        let side = min(bounds.width, bounds.height)
        return NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }

    private func tick() {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else {
            updateTracking()
            return
        }
        let mouse = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let now = ProcessInfo.processInfo.systemUptime
        let previous = gaze.direction
        gaze.advance(toward: CatGaze.target(for: mouse, in: artworkRect), by: now - lastTime)
        lastTime = now
        if abs(gaze.direction.dx - previous.dx) + abs(gaze.direction.dy - previous.dy) > 0.0001 {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        NSGraphicsContext.current?.imageInterpolation = .high
        DockIdleCatArtwork.shared.draw(in: artworkRect, direction: gaze.direction)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
