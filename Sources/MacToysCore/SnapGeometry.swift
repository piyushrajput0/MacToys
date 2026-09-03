import Foundation
import CoreGraphics

/// Where a window should be placed. Mirrors Windows' Aero Snap vocabulary plus the
/// thirds that FancyZones users expect.
public enum SnapAction: String, Codable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centreThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximize, centre

    public var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .leftThird: return "Left Third"
        case .centreThird: return "Centre Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .maximize: return "Maximize"
        case .centre: return "Centre"
        }
    }
}

public enum SnapGeometry {

    /// Computes the target rect for `action` inside `visibleFrame`.
    ///
    /// `visibleFrame` must already exclude the menu bar and Dock. Coordinates are
    /// treated as a plain rectangle: the caller decides whether it is working in
    /// Cocoa (bottom-left origin) or Accessibility (top-left origin) space, and
    /// the vertical actions are named from the caller's point of view. The app
    /// target always passes an Accessibility-space rect, so `topHalf` really is
    /// the top of the screen.
    ///
    /// `gap` insets the result on every side, and additionally halves the gap
    /// between tiles so two snapped windows sit a full `gap` apart rather than
    /// double that.
    public static func frame(for action: SnapAction,
                             in visibleFrame: CGRect,
                             gap: CGFloat = 0) -> CGRect {
        let g = max(0, gap)
        // Outer inset, then compute fractions inside the inset area.
        let area = visibleFrame.insetBy(dx: g, dy: g)
        guard area.width > 0, area.height > 0 else { return visibleFrame }

        let halfGap = g / 2
        let w = area.width
        let h = area.height
        let x = area.minX
        let y = area.minY

        func rect(_ fx: CGFloat, _ fy: CGFloat, _ fw: CGFloat, _ fh: CGFloat) -> CGRect {
            // Shrink each tile by half a gap on the edges that abut another tile.
            // Each *boundary* is rounded rather than each rect: rounding whole
            // rects (CGRect.integral) expands every tile outward, so three
            // thirds of a 1000px screen would each become 334px and overlap.
            // Rounding shared edges keeps adjacent tiles flush and makes the
            // pieces add back up to the screen exactly.
            let left   = (x + w * fx + (fx > 0 ? halfGap : 0)).rounded()
            let top    = (y + h * fy + (fy > 0 ? halfGap : 0)).rounded()
            let right  = (x + w * (fx + fw) - (fx + fw < 1 ? halfGap : 0)).rounded()
            let bottom = (y + h * (fy + fh) - (fy + fh < 1 ? halfGap : 0)).rounded()
            return CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }

        let third: CGFloat = 1.0 / 3.0
        let twoThirds: CGFloat = 2.0 / 3.0

        switch action {
        case .leftHalf:       return rect(0, 0, 0.5, 1)
        case .rightHalf:      return rect(0.5, 0, 0.5, 1)
        case .topHalf:        return rect(0, 0, 1, 0.5)
        case .bottomHalf:     return rect(0, 0.5, 1, 0.5)
        case .topLeft:        return rect(0, 0, 0.5, 0.5)
        case .topRight:       return rect(0.5, 0, 0.5, 0.5)
        case .bottomLeft:     return rect(0, 0.5, 0.5, 0.5)
        case .bottomRight:    return rect(0.5, 0.5, 0.5, 0.5)
        case .leftThird:      return rect(0, 0, third, 1)
        case .centreThird:    return rect(third, 0, third, 1)
        case .rightThird:     return rect(twoThirds, 0, third, 1)
        case .leftTwoThirds:  return rect(0, 0, twoThirds, 1)
        case .rightTwoThirds: return rect(third, 0, twoThirds, 1)
        case .maximize:       return area.integral
        case .centre:
            let cw = (w * 0.6).rounded()
            let ch = (h * 0.7).rounded()
            return CGRect(x: (x + (w - cw) / 2).rounded(),
                          y: (y + (h - ch) / 2).rounded(),
                          width: cw, height: ch)
        }
    }

    /// Repeated presses of the same direction walk through progressively narrower
    /// layouts, the way Windows power users expect from FancyZones and the way
    /// Rectangle behaves on macOS. Returns the first entry when the window does
    /// not currently match any step in the cycle.
    public static func nextInCycle(_ cycle: [SnapAction],
                                   current: CGRect,
                                   visibleFrame: CGRect,
                                   gap: CGFloat = 0,
                                   tolerance: CGFloat = 8) -> SnapAction {
        guard let first = cycle.first else { return .maximize }
        for (index, action) in cycle.enumerated() {
            let candidate = frame(for: action, in: visibleFrame, gap: gap)
            if approximatelyEqual(candidate, current, tolerance: tolerance) {
                return cycle[(index + 1) % cycle.count]
            }
        }
        return first
    }

    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance &&
        abs(a.minY - b.minY) <= tolerance &&
        abs(a.width - b.width) <= tolerance &&
        abs(a.height - b.height) <= tolerance
    }

    /// Cocoa screen coordinates put the origin at the bottom-left of the primary
    /// display with y growing upward. The Accessibility API puts it at the
    /// top-left with y growing downward. Windows must be positioned in AX space,
    /// so every screen rect has to be flipped first. The transform is its own
    /// inverse, which is why one function serves both directions.
    ///
    /// - Parameter primaryHeight: full height (not visibleFrame) of the display
    ///   that contains the global origin, i.e. `NSScreen.screens[0].frame.height`.
    public static func flipVertically(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// Picks the display a window mostly lives on, by intersection area, falling
    /// back to the closest centre when a window is entirely off-screen (which
    /// happens after a display is unplugged).
    public static func bestScreenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        var bestIndex = 0
        var bestArea: CGFloat = -1
        for (i, s) in screens.enumerated() {
            let inter = s.intersection(window)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > bestArea { bestArea = area; bestIndex = i }
        }
        if bestArea > 0 { return bestIndex }

        var closest = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let wc = CGPoint(x: window.midX, y: window.midY)
        for (i, s) in screens.enumerated() {
            let sc = CGPoint(x: s.midX, y: s.midY)
            let d = (sc.x - wc.x) * (sc.x - wc.x) + (sc.y - wc.y) * (sc.y - wc.y)
            if d < bestDistance { bestDistance = d; closest = i }
        }
        return closest
    }

    /// Moves a window to another display, preserving its position and size as
    /// fractions of the old screen so a half-snapped window stays half-snapped.
    /// The result is clamped so the window can never land outside the new screen.
    public static func translate(window: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return window }

        let fx = (window.minX - source.minX) / source.width
        let fy = (window.minY - source.minY) / source.height
        let fw = min(1, window.width / source.width)
        let fh = min(1, window.height / source.height)

        var w = (destination.width * fw).rounded()
        var h = (destination.height * fh).rounded()
        w = min(w, destination.width)
        h = min(h, destination.height)

        var x = (destination.minX + destination.width * fx).rounded()
        var y = (destination.minY + destination.height * fy).rounded()
        x = min(max(x, destination.minX), destination.maxX - w)
        y = min(max(y, destination.minY), destination.maxY - h)

        return CGRect(x: x, y: y, width: w, height: h)
    }
}
