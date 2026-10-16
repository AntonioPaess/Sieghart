# Sprint 5 — Daily context and files

Updated October 12, 2026. Sprint 4 is complete and accepted on the user's “tudo funcionando” report after `f77ac65`. Sprint 5's local implementation is delivered on `sprint-5`; user physical Mac acceptance remains pending. [Delivered behavior and verification](sprint-5-closeout.md) · [Mac test guide](sprint-5-test-guide.md).

## Current checkpoint

- Implemented: shared Calendar state across app/menu/island, day/week/month, selected calendars, next event and meeting links, explicit Calendar consent and denial recovery, local reminders, event/reminder notifications with quiet hours and dismiss/snooze, ten configurable island tool tiles.
- October 12 visual correction: the approved team greeting keeps its choreography and circular light but has no horizontal rectangle. Calendar now includes Gantt in both permission and agenda views, a brief identity-specific hello followed by cached breathing, and a month/agenda layout grouped by day. These are Gantt's presentation surfaces; autonomous specialist execution remains a later integration.
- Delivered next slices: selected-folder downloads, file shelf, reviewed Finder move/rename with optional Finder-only shortcuts, plain text paste, URL cleanup, DMG app copy, capture/annotation/local OCR/QR/color and actual event-driven companion reactions. App/menu/island share each feature's state. All 16 isolated check groups, signed bundle verification and nine local layout/PNG exports pass.
- Remaining gate: physical Mac acceptance of native permissions, Finder/paste/drag/share, screen selection/color, notifications/sleep, live appearance and whole-process resource usage. No app was launched during assistant verification.
- The six fixed characters and their greeting/performance/Retina work are implemented in the working tree. They do not establish that every future specialist tool or connected account already works. Sig remains the principal.

## Core delivery

| Area | Planned outcome |
| --- | --- |
| Calendar and reminders | Repair and reintroduce Calendar after its earlier removal. Day/week/month views, next event, meeting links, calendar selection, explicit access, unavailable/denied recovery and user-created reminders with dismiss/snooze. |
| Notifications | Sieghart cards for reminders and its real task events, with per-module choices, quiet hours, dismiss/snooze and duplicate suppression. Arbitrary other apps' notifications require a verified adapter before being promised. |
| Downloads | Observe only user-selected folders; show actual file availability and completion evidence, open/reveal completed files and retain a useful recent list. Unknown download progress stays unknown; no invented percentages or unattended execution. |
| File shelf | Drop or select file references, see previews, reopen/reveal/share/drag them onward, remove entries and clear temporary state. Keep original files intact. Handle moved/missing files and permission revocation. Local file handling prepares a future upload/email workflow. |
| Clipboard and file helpers | Paste plain text; Finder cut/paste and rename; reviewed URL tracking cleanup preserving functional query data; an explicit disk-image install workflow with destination/conflict handling. These are the existing S5 file requirements. |
| Capture tools | Screenshot selection with basic annotation, text/QR extraction and color picking, with explicit access and cancellation. Advanced recording/editing, selected-region continuous monitoring and camera/media pipelines remain later modules. |
| Companion integration | Real event-driven file received/ready, download completed and upcoming-event/reminder reactions for all six avatars. Same shared lifecycle and interrupted motion behavior; no forced focus, fabricated work or separate mandatory chat page. |

## Implementation order

1. Calendar/reminders and their notification preferences.
2. Selected-folder downloads and the local file shelf.
3. Clipboard/file helpers and capture tools.
4. Companion reactions, cross-surface integration, verification and user Mac acceptance.

App, menu and island must use the same feature state. New tools should fit bounded subpages, remain accessible from the launcher and be selectable for the existing rails. Continue physical MVVM: feature Views/ViewModels, native adapters/helpers in Core, reused components/models/services in Shared. Permission preparation belongs in optional onboarding and feature settings; revocation/disable tears down owned services.

## Exit criteria

- A chosen calendar event/reminder appears once, has a working link/action and can be dismissed/snoozed without duplication after sleep/relaunch.
- Only selected folders are observed; file state is truthful and disabling releases observation. Completed files can be found again.
- Shelf actions preserve original files; moved/missing files report recovery. Destructive/replacement operations expose a concrete review before executing.
- File helpers preserve literal content and useful URL data, fail clearly on unsupported targets and handle destination conflicts.
- Capture works or provides truthful denied/unsupported recovery; cancellation leaves no active capture. Result actions and keyboard equivalents work across app/menu/island.
- All six companions use actual events, respect motion/quiet settings and survive interrupted transitions without replacing a newer action.
- Meaningful unit/integration checks, signed build/package checks and user physical acceptance close the sprint. Assistant verification continues without launching the app or enabling real hardware unless the user changes that instruction.

## Tracks that stay separate

Onboarding storytelling, avatar biographies and the three-minute offline Challenge journey proceed with the user's content and final package target. Upload/email delivery, connected chats, configurable specialist-agent execution and Obsidian/GitHub MCP follow supported adapters in a later integration sprint. The broader module matrix retains media/accessory/island gestures and extended hardware work; ranges such as S5–S7 are planning windows, not additional exit requirements for this core sprint.
