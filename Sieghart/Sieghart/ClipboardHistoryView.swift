import SwiftUI
import AppKit

struct ClipboardHistoryView: View {
    @ObservedObject var clipboard: ClipboardController
    var compact = false
    var showsTitle = true
    var listHeight: CGFloat? = nil
    var dismiss: () -> Void = {}
    @State private var query = ""
    @State private var kind: ClipboardKind?
    @State private var favorites = false
    @State private var selection: UUID?
    @State private var showSettings = false
    @State private var confirmClear = false
    @Environment(\.islandPreview) private var staticPreview
    @FocusState private var searchFocused: Bool
    private var items: [ClipboardEntry] { clipboard.filtered(query: query, kind: kind, pinnedOnly: favorites) }
    private var selected: ClipboardEntry? { items.first { $0.id == selection } ?? items.first }

    var body: some View {
        VStack(alignment: .leading, spacing: compact || listHeight != nil ? 10 : 16) {
            HStack(spacing: 10) {
                if !compact && showsTitle { Label("Keep the things you copy.", systemImage: "doc.on.clipboard").font(.title3.weight(.semibold)) }
                Spacer(minLength: 0)
                Text("Save history").font(.caption)
                Toggle("Save history", isOn: $clipboard.isEnabled).labelsHidden().toggleStyle(WorkspaceSwitchStyle()).fixedSize()
                Button { showSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("History settings").accessibilityLabel("History settings")
            }
            if showSettings { ScrollView { settings }.scrollIndicators(.hidden).frame(maxHeight: compact ? 310 : 330) }
            else {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CompanionStyle.muted)
                    if staticPreview { Text("Search copies").foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading) }
                    else { TextField("Search copies", text: $query).textFieldStyle(.plain).focused($searchFocused)
                        .onSubmit { if let selected { Task { await clipboard.paste(selected, dismiss: dismiss) } } } }
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
                }.padding(10).modifier(WorkspaceSurface(radius: 12))
                HStack(spacing: 8) {
                    filter("All", selected: kind == nil && !favorites) { kind = nil; favorites = false }
                    ForEach(ClipboardKind.allCases, id: \.self) { item in
                        filter(item.rawValue.capitalized, selected: kind == item && !favorites) { kind = item; favorites = false }
                    }
                    filter("Pinned", selected: favorites) { kind = nil; favorites.toggle() }
                }
                if !clipboard.isEnabled && items.isEmpty {
                    empty("Your next copy, kept nearby.", detail: "Enable history to save new copies on this Mac. Text, images and file references stay local.", symbol: "doc.on.clipboard")
                } else if items.isEmpty {
                    empty(query.isEmpty ? "Nothing copied yet." : "No matching copies.", detail: query.isEmpty ? "Copy something in another app. It will appear here." : "Try another word or filter.", symbol: "tray")
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        Group {
                            if staticPreview { VStack(spacing: 6) { ForEach(Array(items.prefix(compact ? 2 : 3))) { row($0) }; Spacer(minLength: 0) } }
                            else { ScrollView { LazyVStack(spacing: 6) { ForEach(items) { row($0) } }.padding(.trailing, 2) }.scrollIndicators(.hidden) }
                        }.frame(width: compact ? nil : 242, height: listHeight ?? (compact ? 160 : 226)).clipped()
                        if !compact, let selected { preview(selected).frame(maxWidth: .infinity, alignment: .topLeading).frame(height: listHeight ?? 226) }
                    }
                    if let selected {
                        HStack(spacing: 10) {
                            Button("Copy") { Task { _ = await clipboard.copy(selected) } }.buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
                            Button("Paste") { Task { await clipboard.paste(selected, dismiss: dismiss) } }.buttonStyle(CompanionButtonStyle(compact: compact))
                                .help("Paste into your previous app. Requires Accessibility access.")
                            Spacer(minLength: 0)
                            Button { clipboard.togglePin(selected.id) } label: { Image(systemName: selected.pinned ? "pin.fill" : "pin") }.buttonStyle(.plain).accessibilityLabel(selected.pinned ? "Unpin copy" : "Pin copy")
                            Button { clipboard.remove(selected.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).accessibilityLabel("Delete saved copy")
                        }
                    }
                }
                HStack {
                    Text(clipboard.status).lineLimit(2)
                    Spacer()
                    if clipboard.isEnabled { Button(clipboard.isPaused ? "Resume" : "Pause") { clipboard.isPaused.toggle() }.buttonStyle(.plain) }
                    Text("\(clipboard.entries.count)/\(clipboard.historyLimit)").monospacedDigit()
                }.font(.caption).foregroundStyle(CompanionStyle.muted)
            }
        }.foregroundStyle(CompanionStyle.ink)
            .onAppear { clipboard.preparePasteTarget(); if !compact { searchFocused = true } }
            .onMoveCommand { direction in
                guard !items.isEmpty else { return }
                let index = items.firstIndex { $0.id == selected?.id } ?? 0
                if direction == .down { selection = items[min(index + 1, items.count - 1)].id }
                if direction == .up { selection = items[max(index - 1, 0)].id }
            }
            .confirmationDialog("Clear saved clipboard history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { clipboard.clear(); selection = nil }
            } message: { Text("This removes saved copies and pins from Sieghart. Your current system clipboard is unchanged.") }
    }
    private func filter(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(.system(size: compact ? 10 : 11, weight: .medium)).buttonStyle(.plain)
            .padding(.horizontal, compact ? 7 : 10).padding(.vertical, 6)
            .foregroundStyle(selected ? CompanionStyle.accentInk : CompanionStyle.muted)
            .background(selected ? CompanionStyle.accent.opacity(0.12) : CompanionStyle.edge.opacity(0.035), in: Capsule())
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func row(_ item: ClipboardEntry) -> some View {
        Button { selection = item.id } label: {
            HStack(spacing: 10) {
                Image(systemName: item.payload.kind == .image ? "photo" : item.payload.kind == .files ? "folder" : "text.alignleft")
                    .foregroundStyle(CompanionStyle.accentInk).frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.payload.title).font(.callout.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(item.sourceName) · \(item.copiedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(CompanionStyle.muted).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if item.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(CompanionStyle.accentInk) }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected?.id == item.id ? CompanionStyle.edge.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).foregroundStyle(CompanionStyle.ink).accessibilityLabel("\(item.payload.title), \(item.sourceName)")
            .contextMenu {
                Button("Copy") { Task { _ = await clipboard.copy(item) } }
                Button("Paste") { Task { await clipboard.paste(item, dismiss: dismiss) } }
                Button(item.pinned ? "Unpin" : "Pin") { clipboard.togglePin(item.id) }
                Button("Delete", role: .destructive) { clipboard.remove(item.id) }
            }
    }
    private func preview(_ item: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("PREVIEW").tracking(1.2); Spacer(); Text(item.payload.kind.rawValue.capitalized) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(CompanionStyle.muted)
            switch item.payload.kind {
            case .text:
                if staticPreview { Text(item.payload.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                else { ScrollView { Text(item.payload.text).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) } }
            case .image:
                if let image = NSImage(data: item.payload.image) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { Text("Image preview unavailable") }
            case .files:
                Group {
                    if staticPreview { VStack(alignment: .leading, spacing: 10) { ForEach(item.payload.files, id: \.self) { Label($0.lastPathComponent, systemImage: "doc").font(.callout) } } }
                    else { ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach(item.payload.files, id: \.self) { Label($0.lastPathComponent, systemImage: "doc").font(.callout).textSelection(.enabled) } } } }
                }
                Text("File references only. The files stay in their original locations.").font(.caption2).foregroundStyle(CompanionStyle.muted)
            }
            Spacer(minLength: 0)
        }.padding(14).modifier(WorkspaceSurface(radius: 15))
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Include images and files"); Spacer(); Toggle("Include images and files", isOn: $clipboard.includeMedia).labelsHidden().toggleStyle(WorkspaceSwitchStyle()) }
            HStack {
                Text("Maximum saved copies"); Spacer()
                ForEach([5, 10, 20], id: \.self) { value in filter("\(value)", selected: clipboard.historyLimit == value) { clipboard.historyLimit = value } }
            }
            Picker("Clean history", selection: $clipboard.cleanup) { ForEach(ClipboardCleanup.allCases) { Text($0.rawValue).tag($0) } }
            if clipboard.cleanup == .afterDays {
                Stepper("After \(clipboard.retentionDays) days", value: $clipboard.retentionDays, in: 1...365)
            }
            Text(clipboard.cleanup == .afterDays ? "Pinned copies stay until you delete them. Pins count toward your chosen limit." : "This rule clears all saved copies, including pins. Closing the app window does not clear history.").font(.caption).foregroundStyle(CompanionStyle.muted)
            Text("Text, images and file references stay on this Mac, within a 40 MB storage ceiling. Password-manager and marked concealed copies are skipped.")
                .font(.caption).foregroundStyle(CompanionStyle.muted)
            Text("Apps to skip · one bundle identifier per line").font(.caption.weight(.medium))
            TextEditor(text: $clipboard.excludedApps).font(.system(.caption, design: .monospaced)).frame(height: compact ? 68 : 88).scrollContentBackground(.hidden).padding(8).modifier(WorkspaceSurface(radius: 10))
            Text("History capture needs no keyboard permission. Direct paste needs Accessibility; copying and ⌘V work without it.").font(.caption).foregroundStyle(CompanionStyle.muted)
            HStack {
                Button("Paste access") { clipboard.openPasteAccess() }.buttonStyle(CompanionButtonStyle(compact: true))
                Spacer()
                Button("Clear history", role: .destructive) { confirmClear = true }.buttonStyle(.plain)
            }
        }
    }
    private func empty(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(CompanionStyle.accentInk)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(CompanionStyle.muted).multilineTextAlignment(.center).frame(maxWidth: 350)
        }.frame(maxWidth: .infinity).frame(height: compact ? 172 : 220)
    }
}
