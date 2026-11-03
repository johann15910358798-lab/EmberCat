import AppKit
import ApplicationServices

struct DockPlacement: Equatable {
    let dockFrame: CGRect
    let screenFrame: CGRect
    let displayID: UInt32
    let scale: CGFloat
    let framesPerSecond: Int
}

enum DockLookup {
    case found(DockPlacement)
    case hidden
    case needsAccessibility
}

/// Reads geometry only. No screenshots, event injection, preference changes, or AX prompts.
@MainActor
final class DockLocator {
    private var dockPID: pid_t?
    private var dockElement: AXUIElement?

    func locate() -> DockLookup {
        let screens = NSScreen.screens
        guard let primary = screens.first,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return .hidden
        }
        let trusted = AXIsProcessTrusted()
        if trusted {
            if dockPID != dock.processIdentifier || dockElement == nil {
                dockPID = dock.processIdentifier
                dockElement = AXUIElementCreateApplication(dock.processIdentifier)
                if let dockElement { AXUIElementSetMessagingTimeout(dockElement, 0.08) }
            }
            if let dockElement,
               let children = attribute(kAXChildrenAttribute, of: dockElement) as? [AXUIElement] {
                for child in children where attribute(kAXRoleAttribute, of: child) as? String == kAXListRole {
                    if let bounds = frame(of: child) {
                        // An offscreen AX list is an auto-hidden Dock, not a reason to guess a position.
                        return placement(for: bounds, primaryTop: primary.frame.maxY, screens: screens,
                                         accessibilityBounds: true)
                            .map(DockLookup.found) ?? .hidden
                    }
                }
            }
        }
        // Older macOS releases expose a tight Dock window without AX permission.
        // Newer releases expose an entire-display surface; reject that surface.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dock.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.dockWindow)),
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  let result = placement(for: bounds, primaryTop: primary.frame.maxY, screens: screens) else { continue }
            return .found(result)
        }
        return trusted ? .hidden : .needsAccessibility
    }

    private func placement(for bounds: CGRect, primaryTop: CGFloat, screens: [NSScreen],
                           accessibilityBounds: Bool = false) -> DockPlacement? {
        var frame = DockOrbitPath.appKitFrame(from: bounds, primaryTop: primaryTop)
        guard DockOrbitPath.isFinite(frame), min(frame.width, frame.height) >= 24,
              min(frame.width, frame.height) <= 240,
              max(frame.width, frame.height) >= 120 else { return nil }
        guard let screen = screens.max(by: { intersectionArea(frame, $0.frame) < intersectionArea(frame, $1.frame) }),
              intersectionArea(frame, screen.frame) >= frame.width * frame.height * 0.85 else { return nil }
        let edgeDistance = min(abs(frame.minY - screen.frame.minY),
                               abs(frame.minX - screen.frame.minX), abs(frame.maxX - screen.frame.maxX))
        guard edgeDistance <= 40, DockOrbitPath(dockFrame: frame, screenFrame: screen.frame) != nil else { return nil }
        if accessibilityBounds {
            frame = Self.alignToVisibleEdge(frame, screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return DockPlacement(dockFrame: frame, screenFrame: screen.frame, displayID: id,
                             scale: screen.backingScaleFactor, framesPerSecond: screen.maximumFramesPerSecond)
    }

    /// AXList describes the item strip, which can sit a few points above the
    /// visible glass. Use the live reserved screen edge when a shown Dock has
    /// one. An auto-hidden Dock's tiny activation strip is not a usable anchor.
    static func alignToVisibleEdge(_ frame: CGRect, screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        if frame.width >= frame.height {
            let reserved = visibleFrame.minY - screenFrame.minY
            let offset = visibleFrame.minY - frame.maxY
            if reserved >= frame.height * 0.75, abs(offset) <= 12 {
                return frame.offsetBy(dx: 0, dy: offset)
            }
        } else if abs(frame.minX - screenFrame.minX) < abs(frame.maxX - screenFrame.maxX) {
            let reserved = visibleFrame.minX - screenFrame.minX
            let offset = visibleFrame.minX - frame.maxX
            if reserved >= frame.width * 0.75, abs(offset) <= 12 {
                return frame.offsetBy(dx: offset, dy: 0)
            }
        } else {
            let reserved = screenFrame.maxX - visibleFrame.maxX
            let offset = visibleFrame.maxX - frame.minX
            if reserved >= frame.width * 0.75, abs(offset) <= 12 {
                return frame.offsetBy(dx: offset, dy: 0)
            }
        }
        return frame
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func attribute(_ key: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(kAXPositionAttribute, of: element),
              let size = attribute(kAXSizeAttribute, of: element),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
