import SwiftUI

struct MouseButtonsSettingsView: View {
    @ObservedObject var controller: MouseButtonController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extra mouse buttons").font(.headline)
            Text("Requires a mouse with extra buttons. Left, right and wheel clicks keep their normal behavior.").font(.caption).foregroundStyle(CompanionStyle.muted)
            Toggle("Back and Forward with side buttons", isOn: $controller.options.navigation)
            Text("Button 4 goes back; button 5 goes forward in Finder, Safari and Chrome. Other apps keep the mouse default.").font(.caption).foregroundStyle(CompanionStyle.muted)
            Toggle("Customize extra buttons", isOn: $controller.options.custom)
            if controller.options.custom {
                ForEach(MouseButtonOptions.buttons, id: \.self) { button in
                    Picker("Button \(button + 1)", selection: Binding(
                        get: { controller.options.bindings[button] ?? .inherit },
                        set: { controller.options.bindings[button] = $0 })) {
                        ForEach(MouseButtonAction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Text("Assignments override the navigation preset. Use navigation preset restores Back/Forward on buttons 4/5; Keep mouse default leaves a button unchanged.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            if controller.options.navigation || controller.options.custom {
                Text(controller.status).font(.caption).foregroundStyle(CompanionStyle.muted)
                Text(controller.lastButton.map { "Last detected: button \($0)" } ?? "No extra button detected yet. Press a side button in another app.").font(.caption)
                Text("Actions use the app's enabled menu commands. Modified clicks and Secure Input keep the mouse default. No keyboard shortcut is generated.").font(.caption).foregroundStyle(CompanionStyle.muted)
                HStack {
                    Button("Open Accessibility settings") { controller.allowAccess() }
                    Button("Retry") { controller.configure() }
                }.buttonStyle(.bordered)
                Button("Locate this copy of Sieghart") { AccessibilityAccess.revealRunningApp() }.font(.caption)
            }
        }
    }
}
