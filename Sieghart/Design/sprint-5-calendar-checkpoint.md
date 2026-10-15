# Sprint 5 — Calendar and reminders checkpoint

October 11, 2026. Implementation slice on branch `sprint-5`; physical Mac acceptance pending.

## Implemented

- Calendar is visible in the workspace, menu bar panel, island tool page and configurable island rail. All three surfaces use one `CalendarViewModel` owned by the island coordinator.
- One retained `EKEventStore` reads day, week and month ranges. Calendar inclusion is local and persisted. The next event scans the following 30 days independently of the current range. Meeting links are accepted only for HTTP(S) URLs from the EventKit URL, location or notes.
- The Calendar page now opens on a dedicated permission card. The button calls EventKit full-access authorization; denied/restricted status sends the user to System Settings. The app does not ask on launch. The signed bundle now includes `NSCalendarsFullAccessUsageDescription` and `com.apple.security.personal-information.calendars`. Their absence in the October 10 build explains why the prior permission attempt could not succeed.
- The expanded island Calendar opens with a six-week month grid, colored event dots and a seven-day agenda beside it. Dates filter the agenda; month arrows, Today and Open Calendar are available. The workspace and menu retain their day/week/month controls.
- The island Your tools menu has ten tiles in two rows. The Dynamic Island editor lets the user replace, swap by drag and reset those ten choices; the selection persists locally. Preferences is available as an alternative tile and remains reachable from the side button.
- User-created reminders persist locally, can be dismissed or postponed ten minutes, and receive stable-identifier local notifications after explicit notification access. Upcoming calendar event alerts have a separate switch and lead time. Quiet hours and stable request identifiers avoid noisy duplicate requests. Both kinds of native alert expose dismiss and ten-minute snooze actions.

## Verification

- `CalendarChecks.swift` passed with injected Calendar and notification adapters. It covers range changes, source selection, next event, persistence, snooze, dismiss, event-alert action routing, quiet-hour rollover, permission revocation and re-request. `ClipboardChecks.swift` passed with ten-tile selection, swap, move, reset and persistence checks.
- The CLI build passed. The signed Debug bundle passed `verify-built-app.sh`, including the built Calendar purpose string and signed capability. The full legacy `run-checks.sh` stopped in its voice integration executable because `UNUserNotificationCenter` cannot resolve that standalone test process as an app bundle; the two affected feature checks were run separately and passed.
- App, menu, island, permission card, ten-tile menu and Dynamic Island editor rendered offscreen with injected data in `Design/Concepts/calendar-*-preview.png`; their layout was inspected. This preview does not establish behavior of the native TCC prompt on the user's Mac.
- Sieghart and Xcode stayed closed. No real Calendar, notification, microphone, clipboard or screen access was exercised.

## Remaining in this slice

A physical Calendar authorization and notification check, including delivery after sleep and relaunch, remains with the user. Test the rebuilt app at `/private/tmp/sieghart-s5-derived/Build/Products/Debug/Sieghart.app`. On its Calendar page, press Allow Calendar Access and accept the macOS dialog. If the page instead shows Open System Settings, grant Sieghart access in Privacy & Security → Calendars, then return to the app. The rest of Sprint 5 proceeds with selected-folder downloads and shelf, file helpers, capture, then actual event-driven companion reactions.

## Reference research and license

- [Vorssaint](https://github.com/vorssaint/vorssaint-utils) documents an optional notch calendar, local selected-folder access, a shelf, URL cleanup and capture tools. Its [permission guide](https://github.com/vorssaint/vorssaint-utils/blob/main/docs/PERMISSIONS.md) confirms an explicit Calendar button and selected-folder scope. Its code is GPL-3.0-or-later; no runtime code was copied into Sieghart's MIT codebase. The EventKit implementation here was written for Sieghart.
- [Apple EventKit guidance](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) requires the full-access usage description for this request; [Apple's Calendar entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.calendars) documents the signed capability. These and Vorssaint's bundle metadata informed the permission repair.
- [Coucou](https://github.com/Louis-CFM/coucou) is an AI-agent companion reference, with MIT source code but separately protected character, name and art in [LICENSE-ASSETS](https://github.com/Louis-CFM/coucou/blob/main/LICENSE-ASSETS.md). No Coucou code or art was copied in this slice. Sieghart keeps its six approved avatars.
- The GitHub aspect found in Vorssaint is public release/version lookup and Homebrew-backed package metadata, not a Calendar requirement. Coucou uses GitHub for its source and agent project workflows. Connected GitHub/MCP and specialist agent execution belong to the later integration cycle, after the local agenda can supply real events. The future user-selected primary avatar will coordinate agenda, well-being, email, finance and knowledge specialists.
