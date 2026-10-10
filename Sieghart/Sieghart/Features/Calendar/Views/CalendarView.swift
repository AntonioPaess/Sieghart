import SwiftUI

struct CalendarView: View {
    @ObservedObject var model: CalendarViewModel
    @Environment(\.islandPreview) private var preview
    var compact = false
    @State private var reminderTitle = ""
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var showsCalendars = false
    @State private var showsPreferences = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            if !compact { Label("Your day", systemImage: "calendar").font(.title3.weight(.semibold)) }
            HStack(spacing: 8) {
                if preview {
                    HStack(spacing: 0) {
                        ForEach(CalendarViewModel.Span.allCases, id: \.self) { item in
                            Text(item.rawValue).font(.caption.weight(item == model.span ? .semibold : .regular))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(item == model.span ? CompanionStyle.edge.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }
                    }.padding(3).background(CompanionStyle.edge.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                } else {
                    Picker("Period", selection: $model.span) {
                        ForEach(CalendarViewModel.Span.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Button { model.shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous period")
                Button { model.selectedDate = Date() } label: { Text("Today") }
                Button { model.shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next period")
            }.buttonStyle(.plain)
            Text(model.dateRange().start.formatted(date: .abbreviated, time: .omitted) + " – " + model.dateRange().end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(CompanionStyle.muted)
            if model.accessState != .fullAccess {
                Text(model.status).font(.callout).foregroundStyle(CompanionStyle.muted)
                Button(model.accessButtonLabel) { model.requestAccessAndRefresh() }.buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
            } else {
                if let next = model.nextEvent {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NEXT EVENT").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(CompanionStyle.muted)
                        Text(next.title).font(.headline)
                        Text(next.startDate.formatted(date: .abbreviated, time: .shortened) + " · " + next.calendarTitle).font(.caption)
                        HStack(spacing: 9) {
                            if next.hasLink { Button("Join meeting") { model.open(next) }.buttonStyle(CompanionButtonStyle(compact: compact)) }
                            if model.eventAlertsEnabled && !model.isEventAlertDismissed(next) {
                                Button("Snooze alert") { model.snoozeEventAlert(next) }.buttonStyle(.plain)
                                Button("Dismiss alert") { model.dismissEventAlert(next) }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(CompanionStyle.edge.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                if model.events.isEmpty { Text("No events in this period.").font(.callout).foregroundStyle(CompanionStyle.muted) }
                ForEach(model.events.filter { $0.id != model.nextEvent?.id }) { event in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(CompanionStyle.accent).padding(.top, 7)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.callout.weight(.medium))
                            Text((event.isAllDay ? "All day" : event.startDate.formatted(date: .abbreviated, time: .shortened)) + " · " + event.calendarTitle)
                                .font(.caption).foregroundStyle(CompanionStyle.muted)
                        }
                        Spacer(minLength: 4)
                        if event.hasLink { Button { model.open(event) } label: { Image(systemName: "video") }.help("Open meeting link").accessibilityLabel("Open meeting link for \(event.title)") }
                    }
                }
                DisclosureGroup("Calendars", isExpanded: $showsCalendars) {
                    ForEach(model.calendars) { source in
                        Toggle(source.title, isOn: Binding(get: { model.isSelected(source.id) }, set: { model.setSelected($0, id: source.id) }))
                    }
                }.font(.caption)
            }
            Divider()
            Text("REMINDERS").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(CompanionStyle.muted)
            HStack(spacing: 7) {
                if preview {
                    Text("Remind me to…").foregroundStyle(CompanionStyle.muted).frame(maxWidth: .infinity, alignment: .leading)
                    Text(reminderDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(CompanionStyle.muted)
                } else {
                    TextField("Remind me to…", text: $reminderTitle)
                    DatePicker("When", selection: $reminderDate, in: Date()..., displayedComponents: [.date, .hourAndMinute]).labelsHidden()
                }
                Button("Add") { model.addReminder(title: reminderTitle, due: reminderDate); reminderTitle = "" }
            }
            ForEach(model.visibleReminders) { reminder in
                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title).font(.callout.weight(.medium))
                        Text(reminder.effectiveDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(CompanionStyle.muted)
                    }
                    Spacer()
                    Button("10 min") { model.snooze(reminder.id) }.help("Postpone 10 minutes")
                    Button { model.dismiss(reminder.id) } label: { Image(systemName: "checkmark") }.help("Dismiss reminder").accessibilityLabel("Dismiss \(reminder.title)")
                }
            }
            DisclosureGroup("Notification preferences", isExpanded: $showsPreferences) {
                Toggle("Reminder notifications", isOn: $model.notificationsEnabled)
                Toggle("Upcoming event alerts", isOn: $model.eventAlertsEnabled)
                if model.eventAlertsEnabled {
                    Picker("Alert before event", selection: $model.eventLeadMinutes) {
                        Text("At start").tag(0)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                    }
                }
                HStack {
                    Text("Quiet hours")
                    Picker("From", selection: $model.quietStart) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }.labelsHidden()
                    Text("to")
                    Picker("To", selection: $model.quietEnd) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }.labelsHidden()
                }
                Button("Allow notifications") { model.requestNotificationAccess() }
                Text("Quiet hours defer reminders until they end. Equal times turn quiet hours off.").font(.caption).foregroundStyle(CompanionStyle.muted)
            }.font(.caption)
            Text(model.status).font(.caption).foregroundStyle(CompanionStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.prepare() }
    }
}
