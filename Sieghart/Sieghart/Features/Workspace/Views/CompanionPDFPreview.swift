import AppKit
import PDFKit
import SwiftUI

struct CompanionPDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url); return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

struct CompanionPDFThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "doc.richtext").font(.system(size: 30)).foregroundStyle(CompanionStyle.accentInk) }
        }.frame(maxWidth: .infinity, maxHeight: 110)
            .task(id: url) {
                let bytes = await Task.detached(priority: .utility) {
                    guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return Data?.none }
                    return page.thumbnail(of: CGSize(width: 320, height: 220), for: .mediaBox).tiffRepresentation
                }.value
                guard !Task.isCancelled, let bytes else { return }
                image = NSImage(data: bytes)
            }
    }
}
