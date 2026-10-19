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
                Button("Allow Accessibility") { model.allowAccess() }
            }.buttonStyle(.bordered)
            Text(model.status).font(.caption).foregroundStyle(CompanionStyle.muted).accessibilityIdentifier("desktop.status")
            TextField("Find an app or window", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { app in
                        Button { model.activate(app: app) } label: {
                            Label("Open \(app.name)", systemImage: "app").frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered)
                    }
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
                    if model.apps.isEmpty && model.windows.isEmpty { Text("Refresh to choose an app or window.").font(.caption).foregroundStyle(CompanionStyle.muted) }
                }
            }.frame(maxHeight: compact ? 190 : 300)
            Text("Layout for the selected window").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(WindowLayout.allCases) { layout in
                    Button(layout.title) { model.apply(layout) }.buttonStyle(.bordered).disabled(model.selectedID == nil)
                }
            }
            Button("Undo last layout") { model.undo() }.disabled(!model.canUndo)
            Divider()
            Toggle("Snap windows at screen edges", isOn: $model.edgeSnapping)
            Text(model.snapStatus).font(.caption).foregroundStyle(CompanionStyle.muted)
            Button("Retry edge snapping") { model.retrySnapping() }.disabled(!model.edgeSnapping)
        }
    }
}
