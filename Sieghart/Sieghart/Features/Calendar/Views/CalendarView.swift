import SwiftUI

struct CalendarView: View {
    @ObservedObject var model: CalendarViewModel
    var events: CompanionEventCenter? = nil
    @Environment(\.islandPreview) private var preview
    var compact = false
    var island = false
    @State private var agendaDay: Date?
    @State private var reminderTitle = ""
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var showsCalendars = false
    @State private var showsPreferences = false
    @State private var showsReminderComposer = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 18 : 22) {
            if model.accessState != .fullAccess {
                permissionCard
            } else {
                ganttHeader
                if !island { periodControls }
                if island || model.span == .month {
                    if compact && !island {
                        monthGrid
                        agenda
                    } else {
                        HStack(alignment: .top, spacing: 22) {
                            monthGrid.frame(width: 228)
                            agenda.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                } else { agenda }
                calendarSelection
                reminders
                notificationPreferences
                Text(model.status).font(.caption).foregroundStyle(CompanionStyle.muted)
                if let events { TaskCardsView(events: events, module: .calendar) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            model.prepare()
            if island && model.span != .month { model.span = .month }
        }
        .onChange(of: model.span) { _, _ in agendaDay = nil }
    }

    private var ganttHeader: some View {
        HStack(spacing: 12) {
            gantt(size: compact ? 64 : 78)
            VStack(alignment: .leading, spacing: 5) {
                Text("GANTT · CALENDAR & ROUTINE")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.1)
                    .foregroundStyle(CompanionStyle.accentInk)
                Text("One commitment at a time.")
                    .font(.system(size: compact ? 18 : 23, weight: .semibold))
                if let next = model.nextEvent {
                    Text("Next: \(next.title)").font(.caption).foregroundStyle(CompanionStyle.muted).lineLimit(2)
                    HStack(spacing: 10) {
                        Text((next.isAllDay ? "All day · " : "") + next.startDate.formatted(date: .abbreviated, time: next.isAllDay ? .omitted : .shortened))
                        if next.hasLink { Button("Join meeting") { model.open(next) }.buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk) }
                        if model.eventAlertsEnabled && !model.isEventAlertDismissed(next) {
                            Menu {
                                Button("Snooze alert") { model.snoozeEventAlert(next) }
                                Button("Dismiss alert") { model.dismissEventAlert(next) }
                            } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Next event alert actions")
                        }
                    }.font(.system(size: 10)).foregroundStyle(CompanionStyle.muted)
                } else {
                    Text("Your plans, with room to breathe.")
                        .font(.caption).foregroundStyle(CompanionStyle.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var periodControls: some View {
        HStack(spacing: 10) {
            if preview {
                HStack(spacing: 0) {
                    ForEach(CalendarViewModel.Span.allCases, id: \.self) { item in
                        Text(item.rawValue).font(.caption.weight(item == model.span ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(item == model.span ? CompanionStyle.edge.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                }.padding(3).background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            } else {
                Picker("Period", selection: $model.span) {
                    ForEach(CalendarViewModel.Span.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 230)
            }
            Spacer(minLength: 0)
            Button { model.shift(-1); agendaDay = nil } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous period")
            Button("Today") { agendaDay = nil; model.selectedDate = Date() }
                .font(.caption.weight(.medium))
            Button { model.shift(1); agendaDay = nil } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next period")
        }.buttonStyle(.plain)
    }

    private var monthGrid: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: model.selectedDate)?.start ?? model.selectedDate
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let weekdays = calendar.veryShortStandaloneWeekdaySymbols
        return VStack(spacing: island ? 10 : 14) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous month")
                Spacer(minLength: 4)
                Text(start.formatted(.dateTime.month(.wide).year())).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next month")
            }.buttonStyle(.plain)
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdays[(index + calendar.firstWeekday - 1) % 7])
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(CompanionStyle.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: island ? 4 : 7) {
                ForEach(0..<42, id: \.self) { index in
                    let date = calendar.date(byAdding: .day, value: index - offset, to: start) ?? start
                    monthDay(date, in: start)
                }
            }
            HStack {
                Button("Today") { agendaDay = calendar.startOfDay(for: Date()); model.selectedDate = Date() }
                Spacer()
                Button { model.openCalendarApp() } label: { Image(systemName: "arrow.up.right.square") }
                    .help("Open Calendar").accessibilityLabel("Open Calendar")
            }.font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk)
        }
        .padding(island ? 12 : 14)
        .background(CompanionStyle.edge.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
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
            model.selectedDate = date
        } label: {
            VStack(spacing: island ? 2 : 3) {
                Text(date, format: .dateTime.day())
                    .font(.system(size: 11, weight: today || selected ? .semibold : .regular))
                    .frame(width: 25, height: island ? 22 : 25)
                    .background(selected ? CompanionStyle.accent : today ? CompanionStyle.edge.opacity(0.10) : .clear, in: Circle())
                    .foregroundStyle(selected ? Color.black : inMonth ? CompanionStyle.ink : CompanionStyle.muted.opacity(0.35))
                HStack(spacing: 2) {
                    ForEach(Array(dots.prefix(3)), id: \.id) { event in
                        Circle().fill(eventColor(event)).frame(width: 3, height: 3)
                    }
                }.frame(height: 3)
            }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var agenda: some View {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: agendaEvents) { event in
            calendar.startOfDay(for: max(event.startDate, agendaDay ?? (island ? Date() : model.dateRange().start)))
        }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(agendaTitle).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                if island && agendaDay != nil {
                    Button("Next 7 days") { agendaDay = nil; model.selectedDate = Date() }
                        .font(.caption).buttonStyle(.plain).foregroundStyle(CompanionStyle.accentInk)
                }
            }
            if groups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A little breathing room.").font(.callout.weight(.medium))
                    Text("No appointments in this period.").font(.caption).foregroundStyle(CompanionStyle.muted)
                }.frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            } else {
                ForEach(groups.keys.sorted(), id: \.self) { day in
                    VStack(alignment: .leading, spacing: 11) {
                        Text(calendar.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(CompanionStyle.muted)
                        ForEach(groups[day] ?? []) { event in eventRow(event) }
                    }
                }
            }
        }
    }

    private var agendaTitle: String {
        if let day = agendaDay { return day.formatted(.dateTime.day().month(.wide)) }
        if island { return "Next 7 days" }
        if model.span == .month { return "Appointments" }
        return model.dateRange().start.formatted(date: .abbreviated, time: .omitted)
            + (model.span == .day ? "" : " – " + model.dateRange().end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))
    }

    private func eventRow(_ event: CalendarEventSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(event.isAllDay ? "All day" : event.startDate.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(CompanionStyle.muted)
                .frame(width: compact ? 48 : 58, alignment: .leading).padding(.top, 3)
            RoundedRectangle(cornerRadius: 2).fill(eventColor(event)).frame(width: 2, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(event.title).font(.system(size: compact ? 12 : 14, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if event.id == model.nextEvent?.id {
                        Text("NEXT").font(.system(size: 8, weight: .semibold)).foregroundStyle(CompanionStyle.accentInk)
                    }
                }
                Text(event.calendarTitle).font(.system(size: 10)).foregroundStyle(CompanionStyle.muted)
            }
            Spacer(minLength: 0)
            if event.hasLink {
                Button { model.open(event) } label: { Image(systemName: "video").font(.system(size: 12)) }
                    .buttonStyle(.plain).padding(.top, 2)
                    .help("Join meeting").accessibilityLabel("Join meeting for \(event.title)")
            }
        }
        .padding(.bottom, 3)
    }

    private var agendaEvents: [CalendarEventSummary] {
        let calendar = Calendar.current
        if let day = agendaDay {
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            return model.events.filter { $0.startDate < end && $0.endDate > day }
        }
        guard island else { return model.events }
        let now = Date()
        let end = calendar.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86_400)
        return model.upcomingEvents.filter { $0.endDate > now && $0.startDate < end }
    }

    private var calendarSelection: some View {
        DisclosureGroup("Calendars shown", isExpanded: $showsCalendars) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(model.calendars) { source in
                    Toggle(isOn: Binding(get: { model.isSelected(source.id) }, set: { model.setSelected($0, id: source.id) })) {
                        HStack(spacing: 6) { Circle().fill(Color(nsColor: source.color)).frame(width: 5, height: 5); Text(source.title) }
                    }
                }
            }.padding(.top, 8)
        }.font(.caption).foregroundStyle(CompanionStyle.muted)
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().opacity(0.6)
            DisclosureGroup("Reminders", isExpanded: $showsReminderComposer) {
                VStack(alignment: .leading, spacing: 9) {
                    if preview {
                        Text("Remind me to…").foregroundStyle(CompanionStyle.muted)
                        Text(reminderDate.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    } else {
                        TextField("Remind me to…", text: $reminderTitle).textFieldStyle(.roundedBorder)
                        DatePicker("When", selection: $reminderDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                    Button("Add reminder") { model.addReminder(title: reminderTitle, due: reminderDate); reminderTitle = "" }
                        .buttonStyle(CompanionButtonStyle(primary: true, compact: compact))
                }.padding(.top, 10)
            }.font(.callout.weight(.medium))
            ForEach(model.visibleReminders) { reminder in
                HStack(spacing: 9) {
                    Button { model.dismiss(reminder.id) } label: { Image(systemName: "circle") }
                        .buttonStyle(.plain).help("Complete reminder").accessibilityLabel("Complete \(reminder.title)")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reminder.title).font(.callout)
                        Text(reminder.effectiveDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(CompanionStyle.muted)
                    }
                    Spacer(minLength: 0)
                    Button("10 min") { model.snooze(reminder.id) }.font(.caption).buttonStyle(.plain).help("Postpone 10 minutes")
                }
            }
        }
    }

    private var notificationPreferences: some View {
        DisclosureGroup("Notification preferences", isExpanded: $showsPreferences) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Reminder notifications", isOn: $model.notificationsEnabled)
                Toggle("Upcoming event alerts", isOn: $model.eventAlertsEnabled)
                if model.eventAlertsEnabled {
                    Picker("Alert before event", selection: $model.eventLeadMinutes) {
                        Text("At start").tag(0)
                        ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                }
                HStack {
                    Text("Quiet hours")
                    Picker("From", selection: $model.quietStart) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }.labelsHidden()
                    Text("to")
                    Picker("To", selection: $model.quietEnd) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }.labelsHidden()
                }
                Button("Allow notifications") { model.requestNotificationAccess() }.buttonStyle(.plain)
                Text("Quiet hours defer reminders until they end. Equal times turn quiet hours off.")
                    .font(.caption).foregroundStyle(CompanionStyle.muted)
            }.padding(.top, 10)
        }.font(.caption).foregroundStyle(CompanionStyle.muted)
    }

    private func eventColor(_ event: CalendarEventSummary) -> Color {
        Color(nsColor: model.calendars.first(where: { $0.id == event.calendarID })?.color ?? .systemBlue)
    }

    private func moveMonth(_ offset: Int) {
        model.selectedDate = Calendar.current.date(byAdding: .month, value: offset, to: model.selectedDate) ?? model.selectedDate
        // A browsed month shows its first day rather than an unrelated current-week agenda.
        agendaDay = island ? model.dateRange().start : nil
    }

    private var permissionCard: some View {
        let denied = model.accessState == .denied || model.accessState == .restricted
        return VStack(spacing: 17) {
            gantt(size: compact ? 112 : 136)
                .background {
                    Ellipse().fill(RadialGradient(colors: [CompanionAvatar.gantt.tint.opacity(0.16), .clear],
                                                  center: .center, startRadius: 0, endRadius: 90))
                        .frame(width: 200, height: 150)
                }
            VStack(spacing: 8) {
                Text("GANTT · CALENDAR & ROUTINE").font(.system(size: 9, weight: .semibold)).tracking(1.1)
                    .foregroundStyle(CompanionStyle.accentInk)
                Text("Let's make room for your day.").font(.system(size: compact ? 22 : 27, weight: .semibold))
                Text(denied
                     ? "Allow Calendar access in System Settings. I'll keep your next commitment close."
                     : "Your next commitment and a gentler reminder, together. You choose which calendars appear.")
                    .font(.callout).foregroundStyle(CompanionStyle.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Button(denied ? "Open System Settings" : "Allow Calendar Access") { model.requestAccessAndRefresh() }
                .buttonStyle(CompanionButtonStyle(primary: true, compact: compact)).disabled(model.isRequestingAccess)
            if model.isRequestingAccess {
                HStack(spacing: 7) { ProgressView().controlSize(.small); Text("Waiting for your permission…").font(.caption) }
            } else {
                Label("Read on this Mac. Your events stay in Calendar.", systemImage: "lock")
                    .font(.system(size: 10)).foregroundStyle(CompanionStyle.muted)
            }
            if model.status.hasPrefix("Calendar permission request failed") {
                Text(model.status).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity, minHeight: island ? 340 : 380)
        .padding(.horizontal, 12)
    }
    @ViewBuilder private func gantt(size: CGFloat) -> some View {
        if let events { CompanionTaskCharacter(events: events, avatar: .gantt, size: size) }
        else { CalendarGantt(size: size) }
    }
}

// A short, identity-specific hello, then cached Retina artwork with composited
// breathing. Removing the page cancels the task and detaches its renderer.
private struct CalendarGantt: View {
    var size: CGFloat
    @Environment(\.islandPreview) private var preview
    @State private var greeting = true
    var body: some View {
        CompanionCharacter(size: size, avatar: .gantt, animation: !preview && greeting ? .hello : .idle)
        .accessibilityLabel("Gantt, your calendar companion")
        .task {
            guard !preview else { return }
            do { try await Task.sleep(for: .seconds(CompanionAnimation.hello.duration + 0.25)) }
            catch { return }
            greeting = false
        }
    }
}
