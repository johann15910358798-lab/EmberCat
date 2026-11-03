import AppKit
import QuartzCore

private final class DockCatPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
private final class DockCatView: NSView {
    private let sprite = CALayer()
    private let footprints = DockPawTrailLayer()
    private let idleCat = DockIdleCatView(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(footprints.layer)
        sprite.name = "dock-cat-sprite"
        sprite.bounds = CGRect(origin: .zero, size: DockOrbitPath.spriteSize)
        sprite.contentsGravity = .resizeAspect
        sprite.magnificationFilter = .linear
        sprite.allowsEdgeAntialiasing = true
        // A narrow pale rim keeps the black silhouette legible on dark desktops.
        sprite.shadowColor = NSColor.white.cgColor
        sprite.shadowOpacity = 0.85
        sprite.shadowRadius = 1.25
        sprite.shadowOffset = .zero
        layer?.addSublayer(sprite)
        idleCat.isHidden = true
        addSubview(idleCat)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(pose: DockOrbitPath.Pose, path: DockOrbitPath, trail: DockPawTrail,
                 color: NSColor, image: NSImage?, scale: CGFloat, resting: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let canvas = path.canvasFrame
        footprints.present(trail, path: path, color: color, scale: scale)
        sprite.position = CGPoint(x: pose.center.x - canvas.minX, y: pose.center.y - canvas.minY)
        sprite.transform = CATransform3DMakeRotation(pose.angle, 0, 0, 1)
        sprite.contentsScale = scale
        sprite.isHidden = resting
        idleCat.frame = path.idleFrame.offsetBy(dx: -canvas.minX, dy: -canvas.minY)
        idleCat.isHidden = !resting
        if let image {
            sprite.contents = image.representations.compactMap { $0 as? NSBitmapImageRep }
                .max(by: { $0.pixelsWide < $1.pixelsWide })?.cgImage
        }
        CATransaction.commit()
    }

    func clearTrail() { footprints.clear() }
    func followMouse(_ enabled: Bool) { idleCat.followsMouse = enabled }
}

/// One transparent, nonactivating surface. A display link moves only the cat layer.
@MainActor
final class DockOrbitController: NSObject {
    private let settings: DockOrbitSettings
    private let locate: @MainActor () -> DockLookup
    private let reduceMotion: @MainActor () -> Bool
    private let windowTitle: String
    private var panel: DockCatPanel?
    private var catView: DockCatView?
    private var displayLink: CADisplayLink?
    private var geometryTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var motion = DockOrbitMotion()
    private var target: DockPlacement?
    private var currentDockFrame: CGRect?
    private var frameKey: String?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var sleeping = false
    private var stopped = false

    var isAnimating: Bool { displayLink != nil }

    init(settings: DockOrbitSettings = .shared,
         locate: (@MainActor () -> DockLookup)? = nil,
         reduceMotion: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
         windowTitle: String = "EmberCat · Dock 跑圈") {
        self.settings = settings
        let locator = DockLocator()
        self.locate = locate ?? { locator.locate() }
        self.reduceMotion = reduceMotion
        self.windowTitle = windowTitle
        super.init()
        observeNotifications()
        configure()
    }

    func update(speed: Double) {
        guard !stopped else { return }
        motion.setSpeed(sleeping ? 0 : speed)
        if panel?.isVisible == true { updateDisplayLink() }
    }

    private func observeNotifications() {
        observers.append(NotificationCenter.default.addObserver(forName: .emberCatDockTrailColorChanged, object: settings, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.present() }
        })
        for name in [Notification.Name.emberCatDockSettingsChanged, NSApplication.didChangeScreenParametersNotification] {
            let object: Any? = name == .emberCatDockSettingsChanged ? settings : nil
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.configure()
                }
            })
        }
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.motion.pause()
                    self?.frameKey = nil
                    self?.refreshLocation()
                }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sleeping = true
                    self.motion.setSpeed(0)
                    self.configure()
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sleeping = false
                    self.motion.setSpeed(0)
                    self.motion.pause()
                    self.configure()
                }
            })
        }
    }

    private func configure() {
        guard settings.isEnabled, !sleeping, !stopped else {
            geometryTimer?.invalidate()
            geometryTimer = nil
            hide()
            if !settings.isEnabled { setStatus(.disabled) }
            return
        }
        if geometryTimer == nil {
            let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshLocation() }
            }
            timer.tolerance = 0.08
            RunLoop.main.add(timer, forMode: .common)
            geometryTimer = timer
        }
        refreshLocation()
    }

    private func refreshLocation() {
        guard settings.isEnabled, !sleeping, !stopped else { return }
        switch locate() {
        case .hidden:
            hide()
            setStatus(.waitingForDock)
        case .needsAccessibility:
            hide()
            setStatus(.needsAccessibility)
        case .found(let placement):
            if target?.dockFrame != placement.dockFrame { motion.clearTrail() }
            if target?.displayID != placement.displayID || currentDockFrame == nil {
                stopDisplayLink()
                motion.pause()
                currentDockFrame = placement.dockFrame
            } else if target?.framesPerSecond != placement.framesPerSecond {
                stopDisplayLink()
            }
            target = placement
            if reduceMotion() { currentDockFrame = placement.dockFrame }
            setStatus(.following)
            present()
            updateDisplayLink()
        }
    }

    private var layoutIsMoving: Bool {
        guard let currentDockFrame, let target else { return false }
        return abs(currentDockFrame.minX - target.dockFrame.minX) > 0.1
            || abs(currentDockFrame.minY - target.dockFrame.minY) > 0.1
            || abs(currentDockFrame.width - target.dockFrame.width) > 0.1
            || abs(currentDockFrame.height - target.dockFrame.height) > 0.1
    }

    private func updateDisplayLink() {
        guard panel?.isVisible == true, !reduceMotion(), !sleeping, !stopped,
              motion.needsTicks || layoutIsMoving else { stopDisplayLink(); return }
        guard displayLink == nil, let catView, let target else { return }
        let link = catView.displayLink(target: self, selector: #selector(tick(_:)))
        let fps = Float(min(120, max(30, target.framesPerSecond)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, fps), maximum: fps, preferred: fps)
        lastTick = ProcessInfo.processInfo.systemUptime
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.25, max(0, now - lastTick))
        lastTick = now
        guard let target, let current = currentDockFrame else { stopDisplayLink(); return }
        if layoutIsMoving {
            let amount = 1 - exp(-elapsed / 0.18)
            let goal = target.dockFrame
            currentDockFrame = CGRect(x: current.minX + (goal.minX - current.minX) * amount,
                                      y: current.minY + (goal.minY - current.minY) * amount,
                                      width: current.width + (goal.width - current.width) * amount,
                                      height: current.height + (goal.height - current.height) * amount)
        } else { currentDockFrame = target.dockFrame }
        if let frame = currentDockFrame, let path = DockOrbitPath(dockFrame: frame, screenFrame: target.screenFrame) {
            motion.advance(by: elapsed, pathLength: path.length)
        }
        present()
        updateDisplayLink()
    }

    private func present() {
        guard let target, let frame = currentDockFrame,
              let path = DockOrbitPath(dockFrame: frame, screenFrame: target.screenFrame) else { return }
        if panel == nil {
            let view = DockCatView(frame: CGRect(origin: .zero, size: path.canvasFrame.size))
            let panel = DockCatPanel(contentRect: path.canvasFrame,
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = windowTitle
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = view
            self.panel = panel
            catView = view
        }
        if panel?.frame != path.canvasFrame { panel?.setFrame(path.canvasFrame, display: true) }
        let reduced = reduceMotion()
        let resting = reduced || motion.isResting
        if resting { motion.park(at: path.idlePhase) }
        let key = reduced ? "reduced-idle" : motion.director.cat.frameKey
        let image: NSImage?
        if frameKey != key {
            image = reduced ? SpriteLibrary.shared.catFrames(for: .idle).first
                : SpriteLibrary.shared.image(for: .cat, director: motion.director)
            frameKey = key
        } else { image = nil }
        catView?.present(pose: path.pose(at: motion.phase), path: path, trail: motion.trail,
                         color: settings.trailColor, image: image, scale: target.scale, resting: resting)
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
        catView?.followMouse(resting && !reduced)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func hide() {
        stopDisplayLink()
        motion.pause()
        catView?.followMouse(false)
        catView?.clearTrail()
        panel?.orderOut(nil)
        target = nil
        currentDockFrame = nil
    }

    private func setStatus(_ status: DockOrbitSettings.Status) {
        if settings.status != status { settings.status = status }
    }

    func shutdown() {
        stopped = true
        geometryTimer?.invalidate()
        geometryTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.removeAll()
        hide()
        panel?.contentView = nil
        panel?.close()
        panel = nil
        catView = nil
    }
}
