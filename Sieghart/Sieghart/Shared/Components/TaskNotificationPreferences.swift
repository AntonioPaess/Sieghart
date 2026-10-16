import SwiftUI

struct TaskNotificationPreferences: View {
    @ObservedObject var events: CompanionEventCenter
    var module: CompanionNotificationModule
    @State private var expanded = false
    var body: some View {
        DisclosureGroup("Task notifications", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 9) {
                Toggle("\(module.rawValue) notifications", isOn: Binding(get: { events.notificationsEnabled(module) }, set: { events.setNotifications($0, for: module) }))
                Button("Allow notifications") { events.requestNotificationAccess() }.buttonStyle(.plain)
                Text("Uses the quiet hours configured in Calendar.").font(.caption).foregroundStyle(CompanionStyle.muted)
                Text(events.status).font(.caption).foregroundStyle(CompanionStyle.muted)
            }.padding(.top, 8)
        }.font(.caption).foregroundStyle(CompanionStyle.muted)
    }
}

