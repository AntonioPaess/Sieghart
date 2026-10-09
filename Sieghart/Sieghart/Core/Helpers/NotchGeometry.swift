import AppKit
import Combine
import SwiftUI

struct NotchGeometry: Equatable {
    let width: CGFloat
    let cutoutWidth: CGFloat
    let cutoutHeight: CGFloat
    let bodyHeight: CGFloat
    var compact = false
    static let cornerRadius: CGFloat = 24
    var contentTop: CGFloat { compact ? 0 : cutoutHeight + 6 }
    var height: CGFloat { contentTop + bodyHeight }
    var size: CGSize { CGSize(width: width, height: height) }
    // The camera gap is part of the activation target, just like both wings.
    // Expanded targets occupy the header only, leaving the controls accessible.
    var activationSize: CGSize { CGSize(width: width, height: compact ? height : max(6, cutoutHeight)) }
    static let fallback = NotchGeometry(width: 480, cutoutWidth: 180, cutoutHeight: 0)

    init(width: CGFloat, cutoutWidth: CGFloat, cutoutHeight: CGFloat, bodyHeight: CGFloat = 192, compact: Bool = false) {
        self.width = width; self.cutoutWidth = cutoutWidth; self.cutoutHeight = cutoutHeight
        // The compact island grows sideways around the camera, never below
        // its physical cutout. Displays without a notch use a 36-point pill.
        self.bodyHeight = compact ? (cutoutHeight > 0 ? cutoutHeight : 36) : bodyHeight
        self.compact = compact
    }

    init(screen: NSScreen, setup: Bool = false, bodyHeight: CGFloat = 192, compact: Bool = false) {
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let measuredWidth = left != nil && right != nil ? max(0, right!.minX - left!.maxX) : 0
        let measuredHeight = measuredWidth > 0 ? max(screen.safeAreaInsets.top, min(left!.height, right!.height)) : 0
        self.init(width: compact ? (measuredWidth > 0 ? measuredWidth + 148 : 240) : min(max(setup ? 520 : 480, measuredWidth + 188), screen.frame.width - 32), cutoutWidth: compact ? measuredWidth : max(measuredWidth, 180), cutoutHeight: measuredHeight, bodyHeight: bodyHeight, compact: compact)
    }
}

enum NotchPresentation: Equatable {
    case home, focusSetup, timer, completion, island, celebration, aiLimits, tools, audio, avatars, clipboard, system, keepAwake, displayPower
}

enum NotchOverlayPolicy {
    static func level(fullScreen: Bool) -> NSWindow.Level {
        fullScreen ? .screenSaver : NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    }

    static func coversDisplay(_ window: CGRect, display: CGRect) -> Bool {
        guard !display.isEmpty, !window.isEmpty else { return false }
        return window.minX <= display.minX + 2 && window.minY <= display.minY + 2 &&
            window.maxX >= display.maxX - 2 && window.maxY >= display.maxY - 2
    }
}

extension NotchGeometry {
    var canvasGeometry: IslandCanvasGeometry { IslandCanvasGeometry(size: size, cutoutWidth: cutoutWidth, cutoutHeight: cutoutHeight, compact: compact) }
}
