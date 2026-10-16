import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FilesView: View {
    @ObservedObject var model: FilesViewModel
    var compact = false
    @Environment(\.islandPreview) private var preview
    @Environment(\.islandReduceMotion) private var reduceMotion
    @State private var surfaceID = UUID()
    @State private var dropping = false
    @State private var selected: Set<UUID> = []
    @State private var renameID: UUID?
    @State private var newName = ""
    @State private var conflict = FileConflictPolicy.cancel
    @State private var urlText = ""
    @State private var urlReview: URLCleanupReview?
    @State private var appID = ""
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                CompanionTaskCharacter(events: model.events, avatar: .toni, size: compact ? 64 : 78,
                                       animates: !reduceMotion, working: model.isBusy)
                VStack(alignment: .leading, spacing: 5) {
                    Text("TONI · COMMUNICATION & FILES").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(CompanionStyle.accentInk)
                    Text("Keep it within reach.").font(.system(size: compact ? 20 : 24, weight: .semibold))
                    Text("Your files stay on this Mac.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
                Spacer(minLength: 0)
            }
            if preview {
                HStack(spacing: 14) { ForEach(FilesViewModel.Page.allCases, id: \.self) { Text($0.rawValue).font(.caption.weight(model.page == $0 ? .semibold : .regular)).foregroundStyle(model.page == $0 ? CompanionStyle.accentInk : CompanionStyle.muted) } }
            } else {
                Picker("Files page", selection: $model.page) { ForEach(FilesViewModel.Page.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            }
            if model.needsReset {
                Text(model.status).font(.callout).foregroundStyle(CompanionStyle.muted)
                Button("Reset saved list") { confirmClear = true }.buttonStyle(CompanionButtonStyle(compact: compact))
            } else {
                switch model.page {
                case .shelf: shelf
                case .downloads: downloads
                case .helpers: helpers
                }
            }
            HStack {
                Text(model.status).font(.caption).foregroundStyle(CompanionStyle.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.isBusy { ProgressView().controlSize(.small); Button("Cancel") { model.cancelAction() }.buttonStyle(.plain).font(.caption) }
            }
            TaskNotificationPreferences(events: model.events, module: model.page == .downloads ? .downloads : .files)
            TaskCardsView(events: model.events, module: model.page == .downloads ? .downloads : .files)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { if !preview { await model.beginSurface(surfaceID) } }
        .onDisappear { if !preview { model.endSurface(surfaceID) } }
        .onReceive(model.$renameTarget) { target in
            if let target { renameID = target.id; newName = target.name }
        }
        .sheet(isPresented: Binding(get: { model.previewURL != nil }, set: { if !$0 { model.previewURL = nil } })) {
            VStack(spacing: 12) {
                if let url = model.previewURL { FileQuickLookView(url: url).frame(width: 620, height: 430) }
                Button("Done") { model.previewURL = nil }.buttonStyle(CompanionButtonStyle(compact: true))
            }.padding(16)
        }
        .confirmationDialog("Clear saved file references? Original files stay intact.", isPresented: $confirmClear) {
            Button("Clear list", role: .destructive) { if model.needsReset { model.resetSavedList() } else { model.clearShelf() } }
        }
    }
    private var shelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { model.chooseFiles() } label: { Label("Choose files", systemImage: "plus") }
                    .buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
                Spacer()
                if !model.shelf.isEmpty { Button("Clear shelf") { confirmClear = true }.font(.caption).buttonStyle(.plain) }
            }
            shelfDropZone
            ForEach(model.shelf) { reference in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        if preview { Image(systemName: selected.contains(reference.id) ? "checkmark.circle.fill" : "circle").font(.caption) }
                        else { Toggle("Select \(reference.name)", isOn: Binding(get: { selected.contains(reference.id) }, set: { if $0 { selected.insert(reference.id) } else { selected.remove(reference.id) } })).labelsHidden().toggleStyle(.checkbox) }
                        Image(systemName: reference.isDirectory ? "folder" : "doc").foregroundStyle(CompanionStyle.accentInk)
                        Text(reference.name).font(.callout.weight(.medium)).lineLimit(2)
                        Spacer(minLength: 0)
                        Button { model.remove(reference.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Remove reference to \(reference.name)")
                    }
                    if let problem = model.problems[reference.id] {
                        Text(problem).font(.caption).foregroundStyle(CompanionStyle.muted)
                        Button("Choose again") { model.chooseRelink(reference) }.buttonStyle(.plain).font(.caption)
                    } else {
                        HStack(spacing: 13) {
                            Button("Open") { Task { await model.open(reference) } }
                            Button("Preview") { Task { await model.open(reference, preview: true) } }
                            Button("Reveal") { Task { await model.open(reference, reveal: true) } }
                            if let url = model.resolvedURLs[reference.id] { ShareLink(item: url) { Text("Share") } }
                        }.font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk)
                    }
                }.padding(12).background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
                .onDrag {
                    guard model.problems[reference.id] == nil, let url = model.resolvedURLs[reference.id] else { return NSItemProvider() }
                    return NSItemProvider(object: url as NSURL)
                }
            }
            if !selected.isEmpty {
                Button("Prepare selected files to move") { model.cut(model.shelf.filter { selected.contains($0.id) }); model.page = .helpers }
                    .buttonStyle(CompanionButtonStyle(compact: compact))
            }
        }
    }
    private var dropZoneContent: some View {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).foregroundStyle(CompanionStyle.accentInk)
                Text("Drop files from Finder.").font(.callout.weight(.medium))
                Text("Park a reference. Drag it onward when you're ready.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 20)
            .background(CompanionStyle.accent.opacity(dropping ? 0.14 : 0.04), in: RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(CompanionStyle.accent.opacity(dropping ? 0.7 : 0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
    }
    @ViewBuilder private var shelfDropZone: some View {
        if preview { dropZoneContent }
        else {
            dropZoneContent
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropping) { providers in
                Task {
                    var urls: [URL] = []
                    for provider in providers.prefix(50) {
                        let data = await FileURLDropLoader.load(provider)
                        if let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { urls.append(url) }
                    }
                    await model.add(urls)
                }
                return !providers.isEmpty
            }
        }
    }
    private var downloads: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Choose folder") { model.chooseFiles(folder: true) }.buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
                Spacer()
                HStack(spacing: 8) {
                    Text("Observe changes").font(.caption)
                    Toggle("Observe changes", isOn: $model.observationEnabled).labelsHidden().toggleStyle(WorkspaceSwitchStyle())
                        .disabled(model.folders.isEmpty)
                }
            }
            if model.folders.isEmpty {
                Text("Choose a downloads folder. Existing files will be shown as available; new partial-file completion can trigger an alert.")
                    .font(.callout).foregroundStyle(CompanionStyle.muted)
            }
            ForEach(model.folders) { folder in
                HStack {
                    Label(folder.reference.name, systemImage: "folder").font(.caption)
                    Spacer()
                    if model.problems[folder.id] != nil { Button("Reconnect") { model.chooseRelink(folder.reference) }.font(.caption) }
                    Button { model.removeFolder(folder.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Stop observing \(folder.reference.name)")
                }
                if let problem = model.problems[folder.id] { Text(problem).font(.caption).foregroundStyle(CompanionStyle.muted) }
            }
            HStack {
                Text("RECENT FILES").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(CompanionStyle.muted)
                Spacer()
                Button("Refresh") { model.refreshDownloads() }.buttonStyle(.plain).font(.caption)
                if !model.recent.isEmpty { Button("Clear list") { model.clearDownloadHistory() }.buttonStyle(.plain).font(.caption) }
            }
            ForEach(model.recent.prefix(compact ? 20 : 40)) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.partial ? "arrow.down.doc" : item.available ? "doc" : "exclamationmark.triangle").foregroundStyle(CompanionStyle.accentInk)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.callout.weight(.medium)).lineLimit(2)
                        Text("\(item.stateTitle) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))").font(.caption).foregroundStyle(CompanionStyle.muted)
                        if !item.partial && item.available {
                            HStack(spacing: 12) {
                                Button("Open") { Task { await model.openDownload(item) } }
                                Button("Reveal") { Task { await model.openDownload(item, reveal: true) } }
                                Button("Keep on shelf") { Task { await model.keepDownload(item) } }
                            }.font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk)
                        }
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 5)
            }
            Text("Partial files show their observed size. A completion percentage is unavailable.").font(.caption).foregroundStyle(CompanionStyle.muted)
        }
    }
    private var helpers: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Move files, with a review.").font(.headline)
                HStack {
                    Button("Choose files to move") { model.chooseCutFiles() }
                    Button("Use Finder selection") { model.cutFinderSelection() }
                }.buttonStyle(CompanionButtonStyle(compact: compact))
                if preview { Text("Existing destination file · \(conflict.rawValue)").font(.caption).foregroundStyle(CompanionStyle.muted) }
                else { Picker("Existing destination file", selection: $conflict) { ForEach(FileConflictPolicy.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.font(.caption) }
                if !model.cutFiles.isEmpty {
                    Text(model.cutFiles.map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(CompanionStyle.muted)
                    HStack {
                        Button("Choose destination") { model.chooseMoveDestination(conflict: conflict) }
                        Button("Current Finder folder") { model.useFinderDestination(conflict: conflict) }
                        Button("Cancel move") { model.cancelCut() }
                    }.font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk)
                }
            }
            Button("Use Finder selection to rename") { model.prepareFinderRename() }.buttonStyle(CompanionButtonStyle(compact: compact))
            if !model.shelf.isEmpty || model.renameTarget != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rename a shelf file.").font(.headline)
                    if preview {
                        Text("Choose a file").font(.caption).foregroundStyle(CompanionStyle.muted)
                        previewField("New file name, including extension")
                    } else {
                        Picker("File", selection: $renameID) {
                            Text("Choose a file").tag(UUID?.none)
                            ForEach(model.shelf) { Text($0.name).tag(Optional($0.id)) }
                            if let target = model.renameTarget, !model.shelf.contains(where: { $0.id == target.id }) { Text(target.name).tag(Optional(target.id)) }
                        }
                        TextField("New file name, including extension", text: $newName)
                    }
                    Button("Review rename") {
                        if let ref = model.shelf.first(where: { $0.id == renameID }) ?? (model.renameTarget?.id == renameID ? model.renameTarget : nil) { model.reviewRename(ref, name: newName, conflict: conflict) }
                    }.buttonStyle(CompanionButtonStyle(compact: compact)).disabled(renameID == nil || newName.isEmpty)
                }
            }
            if let review = model.pendingReview {
                reviewCard(title: "Review \(review.kind.rawValue.lowercased())", rows: zip(review.sources, review.targetNames).map { "\($0.name) → \($1)" }, destination: review.destination.pathHint) {
                    model.confirmReview()
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Clean a link.").font(.headline)
                if preview { previewField("Paste a complete link") }
                else { TextField("Paste a complete link", text: $urlText).textFieldStyle(.roundedBorder) }
                Button("Review tracking cleanup") {
                    do { urlReview = try URLTrackingCleanup.review(urlText) } catch { urlReview = nil; model.report(error.localizedDescription) }
                }.buttonStyle(CompanionButtonStyle(compact: compact))
                if let review = urlReview {
                    Text(review.cleaned).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Text(review.isSigned ? "Signed link kept unchanged." : review.removed.isEmpty ? "No known tracking parameters found." : "Remove: " + review.removed.joined(separator: ", "))
                        .font(.caption).foregroundStyle(CompanionStyle.muted)
                    Button("Copy reviewed link") { Task { await model.copyText(review.cleaned) } }.buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Install from a disk image.").font(.headline)
                Text("Review an app and destination. Its disk image stays intact.").font(.caption).foregroundStyle(CompanionStyle.muted)
                Button("Choose disk image") { model.chooseDiskImage() }.buttonStyle(CompanionButtonStyle(compact: compact))
                if let contents = model.imageContents {
                    Text(contents.imageName).font(.caption)
                    Picker("App", selection: $appID) { Text("Choose app").tag(""); ForEach(contents.apps) { Text($0.name).tag($0.id) } }
                    HStack {
                        Button("Choose install destination") { model.chooseInstallDestination(app: appID, conflict: conflict) }.disabled(appID.isEmpty)
                        Button("Eject image") { model.closeDiskImage() }
                    }.font(.caption).buttonStyle(.plain)
                }
                if let review = model.pendingInstall {
                    reviewCard(title: "Review install", rows: [review.candidate.name + " → " + review.targetName], destination: review.destination.pathHint) { model.confirmInstall() }
                }
            }
        }.disabled(model.isBusy)
    }
    private func previewField(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
            .padding(9).background(CompanionStyle.edge.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
    private func reviewCard(title: String, rows: [String], destination: String, confirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(Array(rows.enumerated()), id: \.offset) { Text($0.element).font(.caption) }
            Text("Destination: " + destination).font(.caption).foregroundStyle(CompanionStyle.muted).textSelection(.enabled)
            HStack {
                Button("Confirm") { confirm() }.buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
                Button("Cancel") { model.cancelReview() }.buttonStyle(.plain)
            }
        }.padding(14).background(CompanionStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor private enum FileURLDropLoader {
    static func load(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            let delivery = FileDropDelivery(continuation)
            let progress = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in delivery.finish(data) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { delivery.finish(nil); progress.cancel() }
        }
    }
}
private final class FileDropDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    func finish(_ data: Data?) { let next = lock.withLock { let next = continuation; continuation = nil; return next }; next?.resume(returning: data) }
}
