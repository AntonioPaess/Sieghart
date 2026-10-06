# Sieghart roadmap

Updated October 5, 2026. This is the current execution plan; older Obsidian checkpoints remain historical. The user authorizes reference-level functional coverage with better usability and an integrated companion. Swift Student Challenge remains the first delivery; the complete Mac utility product continues afterward.

## Status and release gates

- **Sprint 1:** foundation, timer persistence and notch geometry delivered; visual iteration continued in Sprint 2.
- **Sprint 2:** published as `db2ea4f` — implementation closeout: six companions, nine poses, repeated-touch moods, focus configuration, compact island, celebration, voice acknowledgement, shortcut recovery, tools entry, Codex quotas, local token counters and separate spending ledger. Build/headless checks are evidence of implementation, not real-Mac acceptance.
- **Sprint 3:** in progress. First slice implemented: initial six-avatar onboarding, one-time local AI monitoring consent, installed-provider detection, background refresh, live AI island and the full reference dashboard. Voice app launch/search and automatic pricing/billing sources remain next.
- **Open acceptance:** SG-001 companion/voice shortcuts after Spaces/full-screen; real notch placement/animation; microphone permission/recognition. The assistant does not run the app or open Xcode.
- **Calendar:** hidden at the user's request; repair and reintroduction in S5, not a current release gate.
- **Costs:** recorded charges are actual user-entered expenses; token prices produce estimates. Automatic billing imports, current model price sources and dated FX must have verified adapters before being described as automatic spending.

## Sprint 3 — First-run companion and live AI

### Implemented first slice — October 5, 2026

- Two-step onboarding presents all six bundled avatars with names and personalities, saves the initial choice on Finish and preselects an existing choice. Appearance can change it later. The gallery uses shared accessible controls and respects Reduce Motion.
- One local-monitoring consent enables detection of installed Codex/Claude Code using existing sign-in. Declining preserves offline companion/focus use. Opening the dashboard requires no repeated connection step; disconnect removes that provider's activity and stops automatic reconnection.
- Background refresh follows active/completed lifecycle events, model, project and elapsed work. The compact island shows the companion and active provider while keeping camera space and physical notch height. A running focus countdown stays available alongside AI activity.
- The complete reference dashboard includes quota/reset windows, spending, Now, 24 hourly bars, model/project rankings and a 13-week activity heatmap with streak, active days and busiest day. Account daily activity comes from Codex when available; hourly/model/project data is explicitly partial local history.
- USD/BRL token estimates use custom prices and dated FX. Recorded charges remain separate. Missing data stays unavailable; there are no fabricated activity records or invoice amounts.

### Evidence

- Universal signed macOS build; deterministic focus, voice, presentation, usage and lifecycle checks. Clone/stream deduplication, long-turn recovery, completed/idle activity, cache creation and first-run/avatar persistence are covered.
- Read-only live verification detected current Codex work and returned 22 dated account activity buckets. No conversation content is retained. No actual app window, sensor, shortcut registration or microphone was used by the assistant.
- [Full dashboard preview](Sieghart/Design/Concepts/ai-dashboard-preview.png) and [six-avatar onboarding preview](Sieghart/Design/Concepts/onboarding-preview.png) render production views offscreen with clearly labeled sample data.

### Next in Sprint 3

1. Voice launch of installed applications with deterministic resolution, ambiguity handling and honest errors; browser search without sending arbitrary text through a shell. These actions are not implemented yet.
2. Verified automatic model-price, dated FX and billing/import adapters. Custom token estimates are not provider invoices; Codex's tested thread usage did not supply a USD estimate.
3. Verified automatic individual Claude quota access; the dated report import remains available.
4. User Mac acceptance for onboarding, activity/island behavior, permissions and companion/voice shortcuts across Spaces/full-screen.

**Exit:** implemented first run and live AI pass the real Mac checks; voice launch/search have actual action adapters; each automatic source has provenance and unavailable states. Calendar remains hidden until its S5 repair.

## Following delivery order

| Milestone | Outcome |
| --- | --- |
| Challenge track | Three-minute offline companion/focus story, accepted playground destination, physical-sensor compatibility, local resources under edition size limit. Reference screenshots and network integrations stay outside its package. |
| S4 | System monitor, keep awake, audio routing/mixer and power/display essentials. Permission and hardware support are explicit. |
| S5 | Calendar repair/reminders, notifications, selected-folder downloads, clipboard/shelf and core capture tools. |
| S6 | Windows/Dock, keyboard and mouse modules, reversible preference changes and conflict handling. |
| S7 | Maintenance, package/app updates, media/recording, advanced process/network/fan tools; module-specific verification. |

## Complete reference coverage — 77 modules

Reference catalog: [Vorssaint, pinned revision 9066461](https://github.com/vorssaint/vorssaint-utils/blob/906646178553325e76107af78ff04bf352c10adf/Sources/Vorssaint/Core/FeatureCatalog.swift). The screenshots show 73 installed-version modules; the current catalog adds four. Every entry below is retained, including advanced modules. A milestone is sequencing, not a delivery date.

Status: **Partial** = a related implemented slice with remaining acceptance/scope. **Planned** = backlog. Upstream identifiers provide traceability; runtime implementations are Sieghart's own.

### Windows and Dock (7)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `switcher` | App/window switcher | Planned | S6 |
| `dockPreview` | Dock previews | Planned | S6 |
| `dockClick` | Dock click behavior | Planned | S6 |
| `windowMaximizer` | Green-button maximize | Planned | S6 |
| `windowLayout` | Window layouts and edge snapping | Planned | S6 |
| `autoQuit` | Quit on last window close | Planned | S6 |
| `spacesOrder` | Desktop order | Planned | S6 |

### Mouse and keyboard (14)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `scrollInverter` | Invert mouse scrolling | Planned | S6 |
| `scrollHorizontal` | Modifier horizontal scroll | Planned | S6 |
| `focusFollowsMouse` | Focus follows pointer | Planned | S6 |
| `smoothScroll` | Smooth scrolling | Planned | S6 |
| `linearScroll` | Linear scrolling | Planned | S6 |
| `mouseAcceleration` | Mouse acceleration control | Planned | S6 |
| `mouseNavigation` | Side-button navigation | Planned | S6 |
| `mouseButtonShortcuts` | Extra mouse button bindings | Planned | S6 |
| `middleClick` | Three-finger middle click | Planned | S6 |
| `mouseClickDebounce` | Mouse click debounce | Planned | S6 |
| `keyboardDebounce` | Keyboard debounce | Planned | S6 |
| `textSnippets` | Text expansion snippets | Planned | S6 |
| `superKey` | Hyper key | Planned | S6 |
| `quitWindowProtection` | Quit/close protection | Planned | S6 |

### Clipboard and files (7)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `clipboardHistory` | Local clipboard history | Planned | S5 |
| `pastePlain` | Paste plain text | Planned | S5 |
| `finderCutPaste` | Finder cut and paste | Planned | S5 |
| `finderRename` | Rename shortcut | Planned | S5 |
| `shelf` | Temporary file shelf | Planned | S5 |
| `urlCleaner` | Remove URL tracking | Planned | S5 |
| `diskImageInstaller` | Disk image app installer | Planned | S5 |

### Sound (5)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `mixer` | Per-app volume mixer | Planned | S4 |
| `soundOutputSwitcher` | Output switcher | Planned | S4 |
| `audioPriority` | Preferred audio devices | Planned | S4 |
| `micMute` | Global microphone mute | Planned | S4 |
| `musicBlock` | Prevent Music auto-launch | Planned | S4 |

### Energy and displays (4)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `keepAwake` | Keep awake: duration/deadline/lid | Planned | S4 |
| `brightness` | Per-display brightness/power | Planned | S4 |
| `extraBrightness` | XDR extra brightness | Planned | S4 |
| `bluetoothSleep` | Bluetooth on sleep | Planned | S4 |

### Tools (19)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `quickLauncher` | Quick tool panel | Partial — Four widget routes; customizable launch panel pending | S5–S7 |
| `quickToggles` | Quick actions | Planned | S5–S7 |
| `colorPicker` | Screen color picker | Planned | S5–S7 |
| `screenOCR` | Screen text/QR copy | Planned | S5–S7 |
| `cleaningMode` | Screen/keyboard cleaning mode | Planned | S5–S7 |
| `mediaTools` | Image/video/GIF compression | Planned | S5–S7 |
| `cleaner` | Cache and file cleanup | Planned | S5–S7 |
| `uninstaller` | App and leftovers removal | Planned | S5–S7 |
| `homebrew` | Homebrew package management | Planned | S5–S7 |
| `appUpdates` | App updates | Planned | S5–S7 |
| `screenshot` | Screenshot capture/annotation | Planned | S5–S7 |
| `cameraPreview` | Private camera mirror | Planned | S5–S7 |
| `radialMenu` | Radial action menu | Planned | S5–S7 |
| `scratchpad` | Floating scratchpad | Planned | S5–S7 |
| `commandBar` | Command/search bar | Planned | S5–S7 |
| `screenRecorder` | Screen recording/editing | Planned | S5–S7 |
| `wallpaper` | Wallpaper picker | Planned | S5–S7 |
| `killProcess` | Process management | Planned | S5–S7 |
| `portManager` | Listening port management | Planned | S5–S7 |

### Dynamic island (13)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `notch` | Island and control center | Partial — Compact companion/focus island and tools; broader control center pending | S3 + S5 |
| `notchCalendar` | Week/month agenda and meeting links | Planned | S3–S5 |
| `notchNotifications` | New notification cards | Planned | S3–S5 |
| `notchGestures` | Island scroll/swipe gestures | Planned | S3–S5 |
| `notchTimer` | Countdown, stopwatch and Pomodoro | Partial — Pomodoro implemented; standalone countdown/stopwatch pending | S3 + S5 |
| `notchAccessories` | Accessory status and battery alerts | Planned | S3–S5 |
| `notchLyrics` | Lyrics | Planned | S3–S5 |
| `notchQueue` | Playback queue | Planned | S3–S5 |
| `notchLiveEqualizer` | Live audio bars | Planned | S3–S5 |
| `notchDownloads` | Selected-folder downloads | Planned | S3–S5 |
| `notchAgents` | AI limits/tokens/cost/live work | Partial — Codex quota and local counters/ledger; live work and automated sources next | S3 + S5 |
| `notchWatch` | Selected screen-area monitoring | Planned | S3–S5 |
| `notchMascot` | Companion interaction | Partial — Six original companions and reactions; feature-specific interactions expand per module | S3 + S5 |

### System monitor (8)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `monitorCPU` | CPU use and temperature | Planned | S4 |
| `monitorGPU` | GPU use and temperature | Planned | S4 |
| `monitorMemory` | Memory pressure/cache/compression/swap | Planned | S4 |
| `monitorNetwork` | Traffic, apps, local IP and speed test | Planned | S4 |
| `monitorDisk` | Space, I/O, SMART and eject | Planned | S4 |
| `monitorPower` | Battery/power/time/health/cycles | Planned | S4 |
| `connectedDevices` | Connected peripherals | Planned | S4 |
| `fanControl` | Fan status and control | Planned | S4 |

## Foundations beyond the module count

- Onboarding: preset/individual module choices, six avatars, language, optional permissions tied to enabled features, no unnecessary access to finish. Revisit later from Settings.
- Settings: searchable sections, configurable keyboard/mouse shortcuts, startup at login, theme, menu-bar symbol/color, density, module enable/disable and real service teardown.
- Display behavior: physical-notch geometry, capsule on other screens, multiple displays, full-screen and Spaces, lock/unlock, sensible hit targets, pure black compact backplate, no focus theft.
- Island navigation: home/control center, side shortcuts, reorderable modules, compact/expanded states, keyboard routes, music/player selection and volume.
- AI: Codex/Claude first, then OpenCode/Copilot when a verified source exists; quota windows, resets, tokens/cache, models/projects/trends, task elapsed/completion alerts. Read-only existing sign-in with bounded local metadata access.
- Money: distinguish invoices/subscription charges from API-equivalent estimates; model-specific prices with date/source, USD/BRL and dated FX; import/export and retention controls.
- Companion: expresses listening/understood, focus/break, app launch, documents received/carried, downloads, upcoming meeting, success/error and warnings. All six get equivalent functionality. Quiet idle and Reduce Motion remain available.

## What “better” must mean in acceptance

- Onboarding makes a real companion choice and useful modules available in one short flow; each data source explains what will be read.
- No extra connection steps on every visit; permission revocation stops reads and shows recovery.
- AI task state follows lifecycle evidence, with a timestamp; missing/reset data is never fabricated as zero.
- Timers survive sleep/relaunch and count completion once; finishing is readable and accessible.
- Shortcuts recover across Spaces/full-screen and remain configurable.
- Every important action has a keyboard path, meaningful feedback and a comfortable hit target.
- Disabled modules stop services and restore changed preferences where applicable.
- The avatar adds context without hiding controls, covering the camera or increasing compact height.

## Evidence and references

- [39 original screenshot gallery](Sieghart/Design/References/Vorssaint/README.md), with timestamp/hash manifest.
- [Current character artwork](Sieghart/Design/Concepts/avatar-reactions.md) and [app notes](Sieghart/README.md).
- [Known bugs](Sieghart/BUGS.md).
- Reference source is GPL-3.0-or-later; no upstream runtime code was copied into this MIT repository. Symbols carry their own [MIT attribution](Sieghart/THIRD_PARTY_NOTICES.md).
