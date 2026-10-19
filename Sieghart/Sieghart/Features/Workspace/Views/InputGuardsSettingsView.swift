import SwiftUI

struct InputGuardsSettingsView: View {
    @ObservedObject var controller: InputGuardsController
    @State private var newTrigger = ""
    @State private var newReplacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input Guards, Hyper Key & Snippets").font(.headline)
            Text("Filter accidental hardware switch bounce, protect against accidental Quit, map a Hyper key, or expand text snippets.").font(.caption).foregroundStyle(CompanionStyle.muted)

            Toggle("Mouse click debounce", isOn: $controller.options.clickDebounceEnabled)
            if controller.options.clickDebounceEnabled {
                Stepper("Click bounce window: \(controller.options.clickDebounceMs) ms", value: $controller.options.clickDebounceMs, in: ClickDebounceState.windowRange, step: 5)
                    .font(.caption)
            }

            Toggle("Keyboard key debounce", isOn: $controller.options.keyDebounceEnabled)
            if controller.options.keyDebounceEnabled {
                Stepper("Key chatter window: \(controller.options.keyDebounceMs) ms", value: $controller.options.keyDebounceMs, in: KeyDebounceState.windowRange, step: 5)
                    .font(.caption)
            }

            Divider()
            Toggle("Hyper key (⌃⌥⌘⇧)", isOn: $controller.options.superKeyEnabled)
            if controller.options.superKeyEnabled {
                Picker("Hyper key trigger", selection: $controller.options.superKeyTrigger) {
                    ForEach(SuperKeyTrigger.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Hold the trigger key while pressing another key to send Control + Option + Command + Shift.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }

            Divider()
            Toggle("Quit & close confirmation (⌘Q / ⌘W)", isOn: $controller.options.quitProtectionEnabled)
            if controller.options.quitProtectionEnabled {
                Toggle("Also require confirmation for ⌘W (Close Window)", isOn: $controller.options.protectCloseWindow).font(.caption)
                Text("Press ⌘Q (or ⌘W) twice within 1.5 seconds in the active app to confirm.").font(.caption).foregroundStyle(CompanionStyle.muted)
                if let hint = controller.quitHint {
                    Text(hint).font(.caption).foregroundStyle(CompanionStyle.accentInk)
                }
            }

            Divider()
            Toggle("Text expansion snippets", isOn: $controller.options.snippetsEnabled)
            if controller.options.snippetsEnabled {
                HStack(spacing: 8) {
                    TextField("Trigger (e.g. ;sig)", text: $newTrigger).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
                    TextField("Replacement text", text: $newReplacement).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        if controller.addSnippet(trigger: newTrigger, replacement: newReplacement) {
                            newTrigger = ""; newReplacement = ""
                        }
                    }.buttonStyle(.bordered)
                }
                if let error = controller.snippetValidationMessage {
                    Text(error).font(.caption).foregroundStyle(CompanionStyle.accentInk)
                }
                ForEach(controller.options.snippets) { snippet in
                    HStack {
                        Toggle(snippet.trigger, isOn: Binding(
                            get: { snippet.enabled },
                            set: { _ in controller.toggleSnippet(id: snippet.id) }
                        ))
                        Text(snippet.replacement).font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(1)
                        Spacer()
                        Button("Remove") { controller.removeSnippet(id: snippet.id) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }

            if controller.options.enabled {
                Text(controller.status).font(.caption).foregroundStyle(CompanionStyle.muted)
                HStack {
                    Button("Open Accessibility settings") { controller.allowAccess() }
                    Button("Retry") { controller.configure() }
                }.buttonStyle(.bordered)
            }
        }
    }
}
