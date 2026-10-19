import Foundation

enum WindowLayout: String, CaseIterable, Identifiable, Sendable {
    case left, right, topLeft, topRight, bottomLeft, bottomRight, maximize, center
    var id: String { rawValue }
    var title: String {
        switch self {
        case .left: "Left half"
        case .right: "Right half"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .maximize: "Fill usable screen"
        case .center: "Center"
        }
    }
}

/// All geometry below uses Accessibility coordinates: origin at the primary
/// display's top left. Secondary displays may have negative coordinates.
struct DesktopScreen: Equatable, Sendable {
    var frame: CGRect
    var usable: CGRect
    static func accessibilityRect(_ appKitRect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: appKitRect.minX, y: primaryTop - appKitRect.maxY, width: appKitRect.width, height: appKitRect.height)
    }
}
enum WindowGeometry {
    static func valid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height, rect.maxX, rect.maxY].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }
    static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
        valid(lhs) && valid(rhs) && abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
    static func screen(for window: CGRect, in screens: [DesktopScreen]) -> DesktopScreen? {
        guard valid(window) else { return nil }
        let available = screens.filter { valid($0.frame) && valid($0.usable) }
        func area(_ screen: DesktopScreen) -> CGFloat {
            let overlap = window.intersection(screen.frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let best = available.max(by: { area($0) < area($1) }), area(best) > 0 { return best }
        return available.min {
            hypot($0.frame.midX - window.midX, $0.frame.midY - window.midY) < hypot($1.frame.midX - window.midX, $1.frame.midY - window.midY)
        }
    }
    static func frame(_ layout: WindowLayout, current: CGRect, usable: CGRect) -> CGRect? {
        guard valid(current), valid(usable) else { return nil }
        let half = usable.width / 2, height = usable.height / 2
        switch layout {
        case .left: return CGRect(x: usable.minX, y: usable.minY, width: half, height: usable.height)
        case .right: return CGRect(x: usable.minX + half, y: usable.minY, width: half, height: usable.height)
        case .topLeft: return CGRect(x: usable.minX, y: usable.minY, width: half, height: height)
        case .topRight: return CGRect(x: usable.minX + half, y: usable.minY, width: half, height: height)
        case .bottomLeft: return CGRect(x: usable.minX, y: usable.minY + height, width: half, height: height)
        case .bottomRight: return CGRect(x: usable.minX + half, y: usable.minY + height, width: half, height: height)
        case .maximize: return usable
        case .center:
            let width = min(current.width, usable.width), height = min(current.height, usable.height)
            return CGRect(x: usable.midX - width / 2, y: usable.midY - height / 2, width: width, height: height)
        }
    }
    static func snap(at point: CGPoint, screens: [DesktopScreen], threshold: CGFloat = 20) -> (DesktopScreen, WindowLayout)? {
        guard point.x.isFinite, point.y.isFinite, threshold > 0,
              let screen = screens.first(where: { valid($0.frame) && valid($0.usable) && $0.frame.contains(point) }) else { return nil }
        let left = point.x - screen.frame.minX <= threshold, right = screen.frame.maxX - point.x <= threshold
        let top = point.y - screen.frame.minY <= threshold, bottom = screen.frame.maxY - point.y <= threshold
        let layout: WindowLayout?
        if left && top { layout = .topLeft }
        else if right && top { layout = .topRight }
        else if left && bottom { layout = .bottomLeft }
        else if right && bottom { layout = .bottomRight }
        else if left { layout = .left }
        else if right { layout = .right }
        else if top { layout = .maximize }
        else { layout = nil }
        return layout.map { (screen, $0) }
    }
    static func movedWithoutResize(from before: CGRect, to after: CGRect) -> Bool {
        valid(before) && valid(after) && abs(before.width - after.width) <= 2 && abs(before.height - after.height) <= 2 &&
            hypot(before.minX - after.minX, before.minY - after.minY) > 4
    }
}

enum WindowWriteResult: Equatable {
    case applied(CGRect)
    case failed(String)
}

/// Read back the actual frame (apps may impose a minimum size). A failed write
/// attempts to restore both attributes; never report success from an AX return
/// code alone. Closures allow partial failures to be exercised without AX.
@MainActor enum WindowFrameWriter {
    static func write(_ desired: CGRect, read: () -> CGRect?, position: (CGPoint) -> Bool, size: (CGSize) -> Bool) -> WindowWriteResult {
        guard WindowGeometry.valid(desired), let before = read(), WindowGeometry.valid(before) else { return .failed("Window is no longer available. Refresh the list.") }
        if size(desired.size), position(desired.origin), let actual = read(), WindowGeometry.valid(actual) {
            return .applied(actual)
        }
        _ = size(before.size); _ = position(before.origin); _ = size(before.size)
        if let restored = read(), WindowGeometry.matches(restored, before) {
            return .failed("The app refused this layout. The original frame was restored.")
        }
        return .failed("The app refused this layout and could not restore its frame. Check the window.")
    }
}
