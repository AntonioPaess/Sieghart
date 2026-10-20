import SwiftUI

struct DesktopToolsView: View {
    @ObservedObject var model: DesktopController
    var compact = false
    @State private var query = ""
    private var matchingWindows: [DesktopWindow] {
        model.windows.filter { query.isEmpty || "\($0.app.name) \($0.title)".localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Refresh list") { model.refresh() }
            }.buttonStyle(.bordered)
            Button("Open Accessibility settings") { model.allowAccess() }.buttonStyle(.bordered)
            Button("Locate this copy of Sieghart") { AccessibilityAccess.revealRunningApp() }.font(.caption)
            Text("Enable this copy in macOS Privacy & Security, then return and refresh.").font(.caption).foregroundStyle(CompanionStyle.muted)
            Text(model.status).font(.caption).foregroundStyle(CompanionStyle.muted).accessibilityIdentifier("desktop.status")
            Text("1. Refresh the list. 2. Select a window below. 3. Choose a layout. Show brings a window forward; Open activates an app.").font(.caption).foregroundStyle(CompanionStyle.muted)
            TextField("Find an app or window", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Windows — select one for layouts").font(.caption.weight(.semibold))
                    ForEach(matchingWindows) { window in
                        HStack {
                            Button {
                                model.selectedID = window.id
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(window.title.isEmpty ? "Untitled window" : window.title).lineLimit(1)
                                    Text(window.app.name).font(.caption).foregroundStyle(CompanionStyle.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.bordered).tint(model.selectedID == window.id ? CompanionStyle.accent : .secondary)
                                .accessibilityLabel("Select \(window.title), \(window.app.name)")
                                .accessibilityAddTraits(model.selectedID == window.id ? .isSelected : [])
                            Button("Show") { model.activate(window: window.id) }.buttonStyle(.bordered)
                        }
                    }
                    if matchingWindows.isEmpty {
                        Text(model.apps.isEmpty ? "Refresh to choose a window." : "No matching windows. Open a window outside full screen, then refresh.").font(.caption).foregroundStyle(CompanionStyle.muted)
                    }
                    Text("Apps — bring an app forward").font(.caption.weight(.semibold)).padding(.top, 8)
                    ForEach(model.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { app in
                        Button { model.activate(app: app) } label: {
                            Label("Open \(app.name)", systemImage: "app").frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered)
                    }
                }
            }.frame(maxHeight: compact ? 150 : 300)
            Text(model.windows.first(where: { $0.id == model.selectedID }).map { "Layout: \($0.title.isEmpty ? $0.app.name : $0.title)" } ?? "Select a window above to enable layouts")
                .font(.subheadline.weight(.semibold)).lineLimit(2)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(WindowLayout.allCases) { layout in
                    Button(layout.title) { model.apply(layout) }.buttonStyle(.bordered).disabled(model.selectedID == nil)
                }
            }
            Button("Undo last layout") { model.undo() }.disabled(!model.canUndo)
            Divider()
            Toggle("Focus window under pointer", isOn: $model.focusFollowsPointer)
            Text(model.focusStatus).font(.caption).foregroundStyle(CompanionStyle.muted)
            if model.focusFollowsPointer { Button("Retry pointer focus") { model.retryPointerFocus() } }
            Divider()
            Toggle("Snap windows at screen edges", isOn: $model.edgeSnapping)
            Text(model.snapStatus).font(.caption).foregroundStyle(CompanionStyle.muted)
            Button("Retry edge snapping") { model.retrySnapping() }.disabled(!model.edgeSnapping)
            Divider()
            DockSpacesSection(dockSpaces: model.dockSpaces, apps: model.apps)
        }
        .onChange(of: query) { _, _ in
            if !matchingWindows.contains(where: { $0.id == model.selectedID }) { model.selectedID = nil }
        }
    }
}

private struct DockSpacesSection: View {
    @ObservedObject var dockSpaces: DockSpacesController
    let apps: [DesktopApp]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dock, Maximize & Desktop Order").font(.subheadline.weight(.semibold))

            Toggle("Dock window previews", isOn: $dockSpaces.dockPreviewEnabled)
            if dockSpaces.dockPreviewEnabled {
                if !apps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(apps) { app in
                                Button(app.name) { dockSpaces.loadDockPreview(for: app) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
                if !dockSpaces.previewWindows.isEmpty {
                    ForEach(dockSpaces.previewWindows) { item in
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(CompanionStyle.muted, lineWidth: 1)
                                .frame(width: 28 * item.aspectRatio, height: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.caption).lineLimit(1)
                                Text("\(Int(item.frame.width))×\(Int(item.frame.height)) · \(item.isMinimized ? "Minimized" : "Visible")")
                                    .font(.caption2).foregroundStyle(CompanionStyle.muted)
                            }
                            Spacer()
                            Button(item.isMinimized ? "Restore" : "Minimize") {
                                _ = dockSpaces.togglePreviewMinimize(item.id)
                            }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                } else {
                    Text("Select a refreshed app above to preview its windows and minimize/restore state.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }
            }

            Picker("Dock click behavior", selection: $dockSpaces.dockClickBehavior) {
                ForEach(DockClickBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
            }

            Toggle("Green button maximizes to usable desktop", isOn: $dockSpaces.greenButtonMaximizes)
            Text(dockSpaces.zoomStatus).font(.caption).foregroundStyle(CompanionStyle.muted)

            Toggle("Quit app when last window closes", isOn: $dockSpaces.autoQuitEnabled)
            if dockSpaces.autoQuitEnabled {
                Stepper("Auto-quit delay: \(dockSpaces.autoQuitDelaySeconds)s", value: $dockSpaces.autoQuitDelaySeconds, in: DockSpacesController.autoQuitDelayRange)
                    .font(.caption)
                Text(dockSpaces.autoQuitStatus).font(.caption).foregroundStyle(CompanionStyle.muted)
            }

            Toggle("Lock Desktop / Spaces order (disable auto-rearrange)", isOn: $dockSpaces.keepSpacesOrderFixed)
            Text(dockSpaces.spacesStatus).font(.caption).foregroundStyle(CompanionStyle.muted)
            if dockSpaces.savedOriginalMruSpaces != nil {
                Button("Restore original Spaces setting") { dockSpaces.restoreOriginalSpacesOrder() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}

