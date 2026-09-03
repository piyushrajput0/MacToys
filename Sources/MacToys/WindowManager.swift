import AppKit
import ApplicationServices
import MacToysCore

/// Moves and resizes other applications' windows through the Accessibility API.
///
/// This is the Aero Snap replacement. macOS has no public API for positioning
/// another app's window, so AX is the only supported route, and it is the reason
/// this one feature asks for Accessibility permission.
enum WindowManager {

    // MARK: - Coordinate spaces

    /// Height of the display that defines the global origin. Accessibility
    /// measures from the top-left of this screen while Cocoa measures from its
    /// bottom-left, so every rect must be flipped through this value.
    private static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// Usable area of each screen in Accessibility coordinates, menu bar and
    /// Dock already excluded.
    static func screenWorkAreas() -> [CGRect] {
        let h = primaryHeight
        return NSScreen.screens.map { SnapGeometry.flipVertically($0.visibleFrame, primaryHeight: h) }
    }

    // MARK: - Focused window

    struct FocusedWindow {
        let element: AXUIElement
        let app: NSRunningApplication
    }

    static func focusedWindow() -> FocusedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value)
        guard status == .success, let raw = value else { return nil }
        // CFTypeRef -> AXUIElement is not expressible with `as?`, because
        // AXUIElement is a CF type without a Swift bridge.
        guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        return FocusedWindow(element: element, app: app)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef = positionRef, let sizeRef = sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(unsafeBitCast(positionRef, to: AXValue.self), .cgPoint, &origin)
        AXValueGetValue(unsafeBitCast(sizeRef, to: AXValue.self), .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func setFrame(_ rect: CGRect, for window: AXUIElement) -> Bool {
        var origin = rect.origin
        var size = rect.size

        // Order matters. A window that is currently larger than the target may
        // refuse to move because the new origin would push it off screen, and a
        // window with a minimum size may refuse to shrink before it has moved.
        // Setting size, then position, then size again converges for both cases
        // and is what every window manager on macOS ends up doing.
        func apply() {
            if let sizeValue = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            }
            if let posValue = AXValueCreate(.cgPoint, &origin) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
            }
        }
        apply()
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        guard let actual = frame(of: window) else { return false }
        // Apps that resize in discrete steps (terminals, some editors) will land
        // a few pixels off. That is success, not failure.
        return SnapGeometry.approximatelyEqual(actual, rect, tolerance: 12)
    }

    /// A window in macOS's native full-screen mode lives on its own Space and
    /// silently ignores position changes, which reads as "the app is broken".
    /// Detect it so the caller can say something useful instead.
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success,
              let number = value as? Bool else { return false }
        return number
    }

    // MARK: - Actions

    /// Which layouts a direction walks through on repeated presses.
    static func cycle(for action: SnapAction) -> [SnapAction] {
        switch action {
        case .leftHalf:  return [.leftHalf, .leftThird, .leftTwoThirds]
        case .rightHalf: return [.rightHalf, .rightThird, .rightTwoThirds]
        default:         return [action]
        }
    }

    enum SnapResult {
        case moved
        case noWindow
        case fullScreen
        case failed
    }

    static func snap(_ action: SnapAction, gap: CGFloat, cycling: Bool) -> SnapResult {
        guard let focused = focusedWindow() else { return .noWindow }
        if isFullScreen(focused.element) { return .fullScreen }
        guard let current = frame(of: focused.element) else { return .noWindow }

        let areas = screenWorkAreas()
        guard let index = SnapGeometry.bestScreenIndex(for: current, screens: areas) else { return .failed }
        let work = areas[index]

        var target = action
        if cycling {
            let steps = cycle(for: action)
            if steps.count > 1 {
                target = SnapGeometry.nextInCycle(steps, current: current, visibleFrame: work, gap: gap)
            }
        }

        let rect = SnapGeometry.frame(for: target, in: work, gap: gap)
        return setFrame(rect, for: focused.element) ? .moved : .failed
    }

    static func moveToAdjacentDisplay(forward: Bool, gap: CGFloat) -> SnapResult {
        guard let focused = focusedWindow() else { return .noWindow }
        if isFullScreen(focused.element) { return .fullScreen }
        guard let current = frame(of: focused.element) else { return .noWindow }

        let areas = screenWorkAreas()
        guard areas.count > 1 else { return .failed }
        guard let index = SnapGeometry.bestScreenIndex(for: current, screens: areas) else { return .failed }

        let destinationIndex = forward
            ? (index + 1) % areas.count
            : (index - 1 + areas.count) % areas.count

        let rect = SnapGeometry.translate(window: current, from: areas[index], to: areas[destinationIndex])
        return setFrame(rect, for: focused.element) ? .moved : .failed
    }
}
