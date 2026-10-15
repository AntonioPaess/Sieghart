import SwiftUI

struct CalendarView: View {
    @ObservedObject var model: CalendarViewModel
    @Environment(\.islandPreview) private var preview
    var compact = false
    var island = false
    @State private var agendaDay: Date?
    @State private var reminderTitle = ""
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var showsCalendars = false
    @State private var showsPreferences = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            if model.accessState != .fullAccess {
                permissionCard
            } else {
                if !compact { Label("Your day", systemImage: "calendar").font(.title3.weight(.semibold)) }
                if island { islandCalendar }
                else {
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
            }
            if model.accessState == .fullAccess {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            model.prepare()
            if island && model.span != .month { model.span = .month }
        }
    }

    private var islandCalendar: some View {
        HStack(alignment: .top, spacing: 16) {
            monthGrid.frame(width: 212)
            Rectangle().fill(CompanionStyle.edge.opacity(0.18)).frame(width: 1)
            agenda.frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, minHeight: 286, alignment: .topLeading)
    }

    private var monthGrid: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: model.selectedDate)?.start ?? model.selectedDate
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let weekdays = calendar.shortStandaloneWeekdaySymbols
        return VStack(spacing: 10) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                Spacer()
                Text(start.formatted(.dateTime.month(.wide).year())).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
            }.buttonStyle(.plain)
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdays[(index + calendar.firstWeekday - 1) % 7])
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(CompanionStyle.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(0..<42, id: \.self) { index in
                    let date = calendar.date(byAdding: .day, value: index - offset, to: start) ?? start
                    monthDay(date, in: start)
                }
            }
            HStack {
                Button("Today") {
                    let today = Date()
                    agendaDay = calendar.startOfDay(for: today)
                    model.selectedDate = today
                }
                Spacer()
                Button("Open Calendar") { model.openCalendarApp() }
            }.font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk)
        }
    }

    private func monthDay(_ date: Date, in month: Date) -> some View {
        let calendar = Calendar.current
        let selected = agendaDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let today = calendar.isDateInToday(date)
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let day = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        let dots = model.events.filter { $0.startDate < end && $0.endDate > day }
        return Button {
            agendaDay = day
            if !inMonth { model.selectedDate = date }
        } label: {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.day())
                    .font(.system(size: 11, weight: today || selected ? .bold : .regular))
                    .frame(width: 23, height: 23)
                    .background(selected ? CompanionStyle.accent : today ? CompanionStyle.edge.opacity(0.16) : .clear, in: Circle())
                HStack(spacing: 2) {
                    ForEach(Array(dots.prefix(3)), id: \.id) { event in
                        Circle().fill(eventColor(event)).frame(width: 3, height: 3)
                    }
                }.frame(height: 3)
            }
            .foregroundStyle(inMonth ? CompanionStyle.ink : CompanionStyle.muted.opacity(0.45))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }

    private var agenda: some View {
        let items = agendaEvents
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(agendaDay.map { $0.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? "Next 7 days")
                    .font(.callout.weight(.semibold))
                Spacer()
                if agendaDay != nil {
                    Button("Next 7 days") { agendaDay = nil; model.selectedDate = Date() }
                        .font(.caption).buttonStyle(.plain)
                }
            }
            if items.isEmpty {
                Text(agendaDay == nil ? "No upcoming appointments" : "No appointments on this day")
                    .font(.callout).foregroundStyle(CompanionStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 90)
            } else {
                ForEach(items) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(eventColor(event)).frame(width: 6, height: 6).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(event.title).font(.callout.weight(.medium))
                                if event.id == model.nextEvent?.id {
                                    Text("NEXT").font(.system(size: 9, weight: .bold)).foregroundStyle(CompanionStyle.accentInk)
                                }
                            }
                            Text((event.isAllDay ? "All day" : event.startDate.formatted(date: .abbreviated, time: .shortened)) + " · " + event.calendarTitle)
                                .font(.caption).foregroundStyle(CompanionStyle.muted)
                        }
                        Spacer(minLength: 4)
                        if event.hasLink {
                            Button { model.open(event) } label: { Image(systemName: "video") }
                                .help("Open meeting link").accessibilityLabel("Open meeting link for \(event.title)")
                        }
                    }
                }
            }
            DisclosureGroup("Calendars shown", isExpanded: $showsCalendars) {
                ForEach(model.calendars) { source in
                    Toggle(source.title, isOn: Binding(get: { model.isSelected(source.id) }, set: { model.setSelected($0, id: source.id) }))
                }
            }.font(.caption)
        }
    }

    private var agendaEvents: [CalendarEventSummary] {
        let calendar = Calendar.current
        if let day = agendaDay {
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            return model.events.filter { $0.startDate < end && $0.endDate > day }
        }
        let now = Date()
        let end = calendar.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86_400)
        return model.upcomingEvents.filter { $0.endDate > now && $0.startDate < end }
    }

    private func eventColor(_ event: CalendarEventSummary) -> Color {
        Color(nsColor: model.calendars.first(where: { $0.id == event.calendarID })?.color ?? .systemBlue)
    }

    private func moveMonth(_ offset: Int) {
        agendaDay = nil
        model.selectedDate = Calendar.current.date(byAdding: .month, value: offset, to: model.selectedDate) ?? model.selectedDate
    }

    private var permissionCard: some View {
        let denied = model.accessState == .denied || model.accessState == .restricted
        return VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 28))
                .foregroundStyle(CompanionStyle.accentInk)
            Text(denied
                 ? "Allow calendar access in System Settings to see your appointments."
                 : "Read your calendars to show upcoming appointments. Events stay on this Mac.")
                .font(.callout).foregroundStyle(CompanionStyle.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(denied ? "Open System Settings" : "Allow Calendar Access") {
                    model.requestAccessAndRefresh()
                }.buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
                    .disabled(model.isRequestingAccess)
                if model.isRequestingAccess { ProgressView().controlSize(.small) }
            }
            if model.status.hasPrefix("Calendar permission request failed") {
                Text(model.status).font(.caption).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: island ? 310 : 220)
        .padding(.horizontal, 12)
    }
}
