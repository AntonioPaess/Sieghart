# Sprint 5 — Calendar and reminders checkpoint

October 10, 2026. Implementation slice on branch `sprint-5`; physical Mac acceptance pending.

## Implemented

- Calendar is visible in the workspace, menu bar panel, island tool page and configurable island rail. All three surfaces use one `CalendarViewModel` owned by the island coordinator.
- One retained `EKEventStore` reads day, week and month ranges. Calendar inclusion is local and persisted. The next event scans the following 30 days independently of the current range. Meeting links are accepted only for HTTP(S) URLs from the EventKit URL, location or notes.
- Explicit Calendar permission action and denied/restricted recovery. The feature does not ask for access on launch.
- User-created reminders persist locally, can be dismissed or postponed ten minutes, and receive stable-identifier local notifications after explicit notification access. Upcoming calendar event alerts have a separate switch and lead time. Quiet hours and stable request identifiers avoid noisy duplicate requests. Both kinds of native alert expose dismiss and ten-minute snooze actions.

## Verification

- `CalendarChecks.swift` passed with injected Calendar and notification adapters. It covers range changes, source selection, next event, persistence, snooze, dismiss, event-alert action routing, quiet-hour rollover and permission revocation.
- `plutil -lint` passed for the Xcode project. The CLI build passed after running outside the sandbox that had blocked SwiftUI's macro server. A signed Debug bundle passed `verify-built-app.sh` for privacy strings, menu-agent metadata and signature.
- App, menu and island Calendar pages rendered offscreen with injected data in `Design/Concepts/calendar-*-preview.png`; their layout was inspected. This preview does not establish behavior of native controls on the user's Mac.
- Sieghart and Xcode stayed closed. No real Calendar, notification, microphone, clipboard or screen access was exercised.

## Remaining in this slice

A physical Calendar/notification check, including delivery after sleep and relaunch, remains with the user. The rest of Sprint 5 proceeds with selected-folder downloads and shelf, file helpers, capture, then actual event-driven companion reactions.

## Reference research and license

- [Vorssaint](https://github.com/vorssaint/vorssaint-utils) documents an optional notch calendar, local selected-folder access, a shelf, URL cleanup and capture tools. Its [permission guide](https://github.com/vorssaint/vorssaint-utils/blob/main/docs/PERMISSIONS.md) confirms an explicit Calendar button and selected-folder scope. Its code is GPL-3.0-or-later; no runtime code was copied into Sieghart's MIT codebase. The EventKit implementation here was written for Sieghart.
- [Coucou](https://github.com/Louis-CFM/coucou) is an AI-agent companion reference, with MIT source code but separately protected character, name and art in [LICENSE-ASSETS](https://github.com/Louis-CFM/coucou/blob/main/LICENSE-ASSETS.md). No Coucou code or art was copied in this slice. Sieghart keeps its six approved avatars.
- The GitHub aspect found in Vorssaint is public release/version lookup and Homebrew-backed package metadata, not a Calendar requirement. Coucou uses GitHub for its source and agent project workflows. Connected GitHub/MCP and specialist agent execution belong to the later integration cycle, after the local agenda can supply real events. The future user-selected primary avatar will coordinate agenda, well-being, email, finance and knowledge specialists.
