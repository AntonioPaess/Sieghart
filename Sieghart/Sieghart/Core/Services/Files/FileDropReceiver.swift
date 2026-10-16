import AppKit

enum FileReceiverGeometry {
    static let stageHeight: CGFloat = 176
    static let characterSize: CGFloat = 72
    static let footerHeight: CGFloat = 36
    static let contentHeight = stageHeight + footerHeight

    // AppKit screen coordinates start at the bottom; the receiver starts at the top.
    static func normalizedPoint(_ point: CGPoint, in screenRect: CGRect) -> CGPoint {
        guard screenRect.width > 0, screenRect.height > 0,
              point.x.isFinite, point.y.isFinite else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: (point.x - screenRect.minX) / screenRect.width,
                       y: (screenRect.maxY - point.y) / screenRect.height)
    }

    static func characterCenter(for point: CGPoint, in size: CGSize, following: Bool) -> CGPoint {
        let half = characterSize / 2
        let insetX = min(size.width / 2, half + 4)
        let insetY = min(size.height / 2, half + 10)
        let target = following ? CGPoint(x: point.x * size.width, y: point.y * size.height) : CGPoint(x: size.width / 2, y: 78)
        return CGPoint(x: min(size.width - insetX, max(insetX, target.x)),
                       y: min(size.height - insetY, max(insetY, target.y)))
    }
}

protocol FileDropReading: Sendable {
    func read(pasteboard: String, changeCount: Int) async throws -> [URL]
}

final class NativeFileDropReader: FileDropReading, Sendable {
    private let worker = PasteboardWorker()
    func read(pasteboard: String, changeCount: Int) async throws -> [URL] {
        guard let result = await worker.run({ () -> [URL]? in
            let board = NSPasteboard(name: NSPasteboard.Name(pasteboard))
            guard board.changeCount == changeCount, (board.pasteboardItems?.count ?? 0) <= 40,
                  let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty, urls.count <= 40, urls.allSatisfy(\.isFileURL), board.changeCount == changeCount else { return nil }
            return urls
        }), let urls = result, !urls.isEmpty else { throw FileToolError.message("This drag could not be read. Drop up to forty local files again.") }
        try Task.checkCancellation()
        return urls
    }
}

// Drag destinations are independent of hitTest. Mouse clicks still reach the
// island controls underneath; registering a file target never installs a hook.
@MainActor class FileDropTargetView: NSView {
    var onFileEnter: ((Int, CGPoint) -> Bool)?
    var onFileMove: ((Int, CGPoint) -> Void)?
    var onFileExit: ((Int) -> Void)?
    var onFileDrop: ((Int, String, Int) -> Bool)?
    private var accepted = false
    private var dropped = false
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    private func point(_ sender: any NSDraggingInfo) -> CGPoint { window?.convertPoint(toScreen: sender.draggingLocation) ?? sender.draggingLocation }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dropped = false
        accepted = sender.draggingPasteboard.types?.contains(.fileURL) == true && sender.draggingSourceOperationMask.contains(.copy)
            && onFileEnter?(sender.draggingSequenceNumber, point(sender)) == true
        return accepted ? .copy : []
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard accepted else { return [] }
        onFileMove?(sender.draggingSequenceNumber, point(sender)); return .copy
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        if accepted, !dropped, let sender { onFileExit?(sender.draggingSequenceNumber) }
        accepted = false
    }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { accepted }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard accepted else { return false }
        dropped = onFileDrop?(sender.draggingSequenceNumber, sender.draggingPasteboard.name.rawValue, sender.draggingPasteboard.changeCount) == true
        return dropped
    }
    override func draggingEnded(_ sender: any NSDraggingInfo) {
        if accepted && !dropped { onFileExit?(sender.draggingSequenceNumber) }
        accepted = false
    }
}
