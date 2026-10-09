import SwiftUI

struct KeepAwakeView: View {
    @ObservedObject var controller: KeepAwakeViewModel
    var compact = false
    @State private var showsConditions = false
    @Environment(\.islandPreview) private var preview
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(controller.status, systemImage: controller.holding ? "cup.and.saucer.fill" : "moon.zzz").font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(controller.enabled ? "Stop" : "Start") { if controller.enabled { controller.stop() } else { controller.start() } }.buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
            }
            if let seconds = controller.remaining, controller.enabled { Text(Duration.seconds(seconds).formatted(.time(pattern: .hourMinuteSecond))).monospacedDigit().font(.title2) }
            UtilityTabs(choices: AwakeMode.allCases, selection: $controller.request.mode, title: { $0.rawValue }).disabled(controller.enabled)
            switch controller.request.mode {
            case .duration:
                HStack { Text("Keep awake for"); Spacer(); Group { if preview { Text("\(controller.request.minutes) min ⌄").foregroundStyle(CompanionStyle.accentInk) } else { Picker("Duration", selection: $controller.request.minutes) { ForEach([5, 15, 30, 60, 120, 240, 480, 1440], id: \.self) { Text("\($0) min").tag($0) } }.labelsHidden().frame(width: 115) } } }.disabled(controller.enabled)
            case .until: DatePicker("Until", selection: $controller.request.until, displayedComponents: [.date, .hourAndMinute]).disabled(controller.enabled)
            case .indefinite: Text("Stays active until you stop it or quit Sieghart.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }
            UtilityToggle(title: "Keep display awake too", isOn: $controller.request.keepDisplay).toggleStyle(WorkspaceSwitchStyle())
            DisclosureGroup("Conditions & restoration", isExpanded: $showsConditions) {
                VStack(alignment: .leading, spacing: 12) {
                    UtilityToggle(title: "Only while connected to power", isOn: $controller.request.onlyOnAC)
                    UtilityToggle(title: "Only with an external display", isOn: $controller.request.externalDisplayOnly)
                    UtilityToggle(title: "Resume valid session on next launch", isOn: $controller.request.restoreOnLaunch)
                    Menu {
                        ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }, id: \.processIdentifier) { app in
                            Button {
                                guard let id = app.bundleIdentifier else { return }
                                if controller.request.applications.contains(id) { controller.request.applications.removeAll { $0 == id } } else { controller.request.applications.append(id) }
                            } label: { Label(app.localizedName ?? "App", systemImage: controller.request.applications.contains(app.bundleIdentifier ?? "") ? "checkmark" : "app") }
                        }
                        Divider(); Button("Any app") { controller.request.applications = [] }
                    } label: { Text(controller.request.applications.isEmpty ? "While any app is running" : "While selected apps run (\(controller.request.applications.count))") }
                    Text("Closing the lid still follows macOS hardware rules. For closed-lid work, use a supported docked setup with power and an external display.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }.padding(.top, 10).toggleStyle(WorkspaceSwitchStyle())
            }
            if let error = controller.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onChange(of: controller.request) { _, _ in controller.saveOptions() }
    }
}
