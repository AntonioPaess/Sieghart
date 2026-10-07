# Sieghart roadmap

Updated October 6, 2026. This is the current execution plan; older Obsidian checkpoints remain historical. The user authorizes reference-level functional coverage with better usability and an integrated companion. Swift Student Challenge remains the first delivery; the complete Mac utility product continues afterward.

## Status and release gates

- **Sprint 1:** foundation, timer persistence and notch geometry delivered; visual iteration continued in Sprint 2.
- **Sprint 2:** published as `db2ea4f` — implementation closeout: six companions, nine poses, repeated-touch moods, focus configuration, compact island, celebration, voice acknowledgement, shortcut recovery, tools entry, Codex quotas, local token counters and separate spending ledger. Build/headless checks are evidence of implementation, not real-Mac acceptance.
- **Sprint 3:** in progress. First slice implemented: initial six-avatar onboarding, one-time local AI monitoring consent, installed-provider detection, background refresh, live AI island and the full reference dashboard. Automatic model pricing/FX, exact chart details, island interaction corrections and the glass presentation with smoother avatars are also implemented. Voice app launch/search and billing imports remain next.
- **Open acceptance:** SG-001 companion/voice shortcuts after Spaces/full-screen; real notch placement/animation; microphone permission/recognition. The assistant does not run the app or open Xcode.
- **Calendar:** hidden at the user's request; repair and reintroduction in S5, not a current release gate.
- **Costs:** recorded charges are actual user-entered expenses; token prices produce estimates. Official model price tables and dated USD/BRL FX adapters are implemented and verified against live public responses. They calculate API-equivalent estimates. Invoice imports remain planned.

## Sprint 3 — First-run companion and live AI

### Implemented first slice — October 5, 2026

- Two-step onboarding presents all six bundled avatars with names and personalities, saves the initial choice on Finish and preselects an existing choice. Appearance can change it later. The gallery uses shared accessible controls and respects Reduce Motion.
- One local-monitoring consent enables detection of installed Codex/Claude Code using existing sign-in. Declining preserves offline companion/focus use. Opening the dashboard requires no repeated connection step; disconnect removes that provider's activity and stops automatic reconnection.
- Background refresh follows active/completed lifecycle events, model, project and elapsed work. The compact island shows the companion and active provider while keeping camera space and physical notch height. A running focus countdown stays available alongside AI activity.
- The complete reference dashboard includes quota/reset windows, spending, Now, 24 hourly bars, model/project rankings and a 13-week activity heatmap with streak, active days and busiest day. Account daily activity comes from Codex when available; hourly/model/project data is explicitly partial local history.
- Automatic per-model prices use bundled facts, official daily OpenAI/Claude updates and persistent fallback. Logged tiers, per-request long context and cache costs are considered. Unknown prices produce a disclosed unpriced token count/≥ lower bound. Frankfurter supplies automatic dated USD/BRL conversion; explicit custom overrides remain possible. Recorded charges stay separate.

### Interaction and precision corrections — October 6, 2026

- Click opens the island. Hover only gives visual feedback, including idle compact state. All expanded pages collapse on pointer exit with a short crossing allowance. Saved focus completion never hijacks AI or normal navigation.
- Appearance saves Small/Medium/Large widget sizes; expanded content scales consistently and compact camera height stays exact.
- Provider logos/selectors follow actual usage/readings, not installation alone. Model/project rows offer exact integers on hover/accessibility; older completed history recovers model context when present.
- Hourly hover/selection gives range, total, input/output/cache and API-equivalent value. Heatmap hover/selection gives exact dated usage. Missing metadata remains explicit.
- Modifier shortcuts now prefer a common-mode listen-only session event tap, with interruption recovery; regular keys retain global Carbon registration and a permitted fallback. Real Mac acceptance remains open.

### Glass island and companion motion — October 6, 2026

- Attached shoulder contour, translucent glass body, native Liquid Glass on macOS 26 and behind-window blur on older supported macOS. The camera strip and compact island remain black. Reduce Transparency provides an opaque fallback.
- Three selectable modes (Timer, Pomodoro and Stopwatch), with an adjustable focus minute ruler, glass break/round controls and explicit Start actions. Circular quick access controls around the surface; the bottom companion control opens the selected avatar. AI cards share the translucent chrome.
- Native contour transitions reserve their full window bounds, keep content at its destination layout, and reveal it after the shell grows. Closing hides departing content and contracts the silhouette. Reduce Motion bypasses movement.
- The user approved Simple Companions. All six are implemented as native minimal shapes with continuous 60 Hz gaze, blinking, breathing, mood interpolation and gentle squash/stretch. Onboarding, Appearance, island and menu use the same native family. Saved identities persist. Legacy sprite sheets remain archived and are excluded from app resources; Reduce Motion keeps static readable states.
- Challenge product text uses only Sieghart branding. External research photographs stay outside the application resources and Challenge package. No external application source code is shipped.

### Click regression and timer completion — October 6, 2026

- SG-002 records the user's renewed click failure. Native activation and SwiftUI hosting now explicitly accept first mouse, the transparent strip keeps full opacity while its background stays clear, its target covers the compact island wings, and its click uses one synchronous toggle route. The second strip click collapses the island. Physical cross-app delivery remains unverified.
- Timer and Stopwatch join Pomodoro in both app and island. Persisted countdown deadlines and stopwatch start/accumulated dates survive pause, sleep and relaunch. Stopwatch supports tenths/hours. Utility clocks never increase focus completion counts. Mode selection never starts a clock; pause/reset preserve open controls.
- Reference influence is selective, not a requirement to duplicate every visual component. Keep the companion central and retain Sieghart's palette/control choices. Detailed robot bodies were rejected; the implemented native companions follow the minimal eye/dot direction in [the approved board](Sieghart/Design/Concepts/avatar-simple-studies.png).
- [Timer](Sieghart/Design/Concepts/timer-timer-preview.png), [Pomodoro](Sieghart/Design/Concepts/timer-pomodoro-preview.png) and [Stopwatch](Sieghart/Design/Concepts/timer-stopwatch-preview.png) are production-view renders. The approved board is generated concept art; [production reactions](Sieghart/Design/Concepts/avatar-reactions-preview.png) and [motion](Sieghart/Design/Concepts/simple-companions-motion.gif) are native offscreen renders.

### Simple Companions and full-screen follow-up — October 6, 2026

- User approval makes the minimal six-character board the current production direction. Native shapes and eye parameters replace raster pose swapping across every companion surface; no elaborate bodies or accessories. The motion preview is sampled at 20 fps from the 60 Hz native animation.
- SG-002 follow-up: the activation header spans the complete current island width. Center/wings share native hit testing, with a bounded camera-click fallback when another app receives the event. Frame constraints no longer move overlays away from their requested camera band. A visible-only pointer point check covers missing tracking events.
- Pointer exit grants 800 ms to cross between controls. Keyboard reveals grant four seconds to reach them; entering cancels the deadline. Explicit closure is immediate, and automatic completion retains its separate announcement duration.
- SG-001 follow-up: healthy shortcut registrations stay installed across app/Space changes. Carbon dispatches through the application event target; permitted session/AppKit monitors handle regular keys even after successful Carbon setup. A per-action gate rejects duplicate backend delivery. Both overlays explicitly support full-screen auxiliary placement along with cross-app/all-Spaces presence.
- Implementation checks cover center/wing native hit tests, AI/countdown/stopwatch opening, duplicate shortcut delivery, repeated gestures, entry cancellation and approach grace. Physical Mac acceptance remains open for full-screen/other-Space delivery and camera-area clicks.

### Companion depth, main app and borderless hover — October 6, 2026

- The user's supplied Simple Companions board defines shape, proportions and palette. Minimal artwork now has 2.5D depth: matte gradients, layered shadows, recessed CRT visor, curved ivory/coral Paper Pal fold and subtle gaze perspective. This remains native 2D artwork, not a 3D rig. [Supplied reference](Sieghart/Design/Concepts/simple-companions-depth-reference.png) · [Production depth preview](Sieghart/Design/Concepts/simple-companions-depth-preview.png).
- The production main window now shares glass cards, quiet lilac lighting, a refined sidebar and consistent typography across Overview, all three Timers, grouped Activation preferences, Appearance and AI limits. The selected companion appears in the sidebar and Overview; active countdown/stopwatch values use the correct clock. Onboarding shares the same surfaces and six-avatar gallery.
- The user rejected the compact island's blue/lilac selection-looking contour. Both its SwiftUI hover outline and native compact edge are removed. Hover changes the companion expression without changing the black shell, opening the island or drawing a selection border. Keyboard actions and VoiceOver remain available.
- [Overview](Sieghart/Design/Concepts/app-overview-preview.png), [Appearance](Sieghart/Design/Concepts/app-appearance-preview.png), [Timers](Sieghart/Design/Concepts/app-timers-preview.png), [Activation](Sieghart/Design/Concepts/app-activation-preview.png), [AI](Sieghart/Design/Concepts/app-ai-preview.png) and [compact hover](Sieghart/Design/Concepts/compact-hover-preview.png) are offscreen production renders. Example data stays separate from real readings; native glass and full-screen clicks remain physical Mac acceptance checks.

### Evidence

- Universal signed macOS build; deterministic focus, voice, presentation, usage and lifecycle checks. Clone/stream deduplication, long-turn recovery, completed/idle activity, cache creation and first-run/avatar persistence are covered.
- Read-only live verification detected current Codex work and returned 22 dated account activity buckets. No conversation content is retained. No actual app window, sensor, shortcut registration or microphone was used by the assistant.
- [Full dashboard preview](Sieghart/Design/Concepts/ai-dashboard-preview.png) and [six-avatar onboarding preview](Sieghart/Design/Concepts/onboarding-preview.png) render production views offscreen with clearly labeled sample data.

### Before Sprint 4 — Layout, menu and audio — October 6, 2026

- Larger contour-aware horizontal margins; Companion no longer repeats grid/voice/settings/close controls inside its content. Seven implemented tools use a four-column launcher. Side audio access replaces the duplicated voice shortcut; Voice stays in the tool grid/menu and its global shortcut.
- AI uses equal-width, equal-height limits/spending cards, current work, an hourly chart with exact hover detail, model/project rankings and 13-week activity. Connections/pricing details open in a separate sheet. The viewport stays bounded at 470 points rather than growing with details.
- Timer, Pomodoro and Stopwatch share text tabs and a horizontal clock layout. Countdown/focus use a drag/VoiceOver-adjustable ruler. Pomodoro break/round/auto-break options fit one row. Explicit start, pause, reset and finish retain the existing persisted timer model.
- Menu bar uses Companion / Timers / AI / Audio / Avatars subpages in a 380-point-wide panel with natural page heights. All six companions are selectable there; the choice is shared with onboarding, app and island.
- Core audio is implemented now: output volume, default input/output device selection, supported input gain/mute, app discovery with helper ownership, native installed app icons and AirPods/device identity, app volume/mute via private Core Audio process taps and aggregate playback. Explicit opt-in, local-only processing, saved gains but capture disabled on launch, incompatible-format errors and route teardown are implemented. Mixer/device/microphone subpages and horizontal app scrolling keep height bounded. Real device and permission acceptance remains open; pinning/order/device priorities are future S4 work.
- Eight isolated check groups and production offscreen previews cover implementation. No app/Xcode window, sensor, microphone, system-audio capture or real shortcut is started by verification. Physical SG-001/SG-002 and audio acceptance are not claimed closed.

### October 6 evening — User-reported corrections

- Menu panel reduced from 560 × 548 to 380 wide and natural page heights (Companion about 297). Compact timers and audio avoid the previous empty vertical area.
- Actual built-package omission of `NSAudioCaptureUsageDescription` fixed through an explicit merged Info.plist. Enable app mixer now starts the public macOS permission path; denial/retry/settings and stale-request cancellation are implemented. Mixer shows at most five real running apps plus Master, prioritizing playback/connected apps. Waiting apps have unavailable sliders until they connect to audio. No placeholder towers.
- Stereo process mixdown replaces a single device stream; mono Bluetooth calls, planar outputs, unity passthrough and preserving an existing route on failed replacement are handled. WhatsApp playback and permission UI still require real Mac confirmation (SG-004).
- Island top edge overscans one physical pixel; native contour and first-click focus strokes removed. All six avatars breathe/sway and float a fading “z” while asleep.
- Installed-app voice launch implemented in English/Portuguese with exact local resolution, ambiguity/failure feedback and no shell execution. Isolated tests inject the launcher.
- Repeated full-screen shortcut report remains open (SG-001). Menu-bar agent metadata, application-target Carbon dispatch and authorized event-tap health recovery address the setup. Actual input and visibility acceptance remains required.
- Three additional issue photos archived with SHA-256 verification. README, production previews, bug tracker and Obsidian checkpoint updated. Sprint 3 remains active; Sprint 4 has not started.

### Next in Sprint 3

1. Browser search through a deterministic action adapter. Installed-app voice launch is now implemented; physical speech/app-launch acceptance remains open.
2. Billing/import adapters and broader historical coverage. Automatic price/FX sources are implemented; values are API equivalents and local history remains partial.
3. Verified automatic individual Claude quota access; the dated report import remains available.
4. Before Sprint 4: Mac acceptance of the refreshed bounded panels/menu tabs and audio mixer: speakers/AirPods, capture permission grant/denial, app mute, output changes and unplugging devices.
5. User Mac acceptance for onboarding, activity/island behavior, permissions and companion/voice shortcuts across Spaces/full-screen.

**Exit:** implemented first run and live AI pass the real Mac checks; voice launch/search have actual action adapters; each automatic source has provenance and unavailable states. Calendar remains hidden until its S5 repair.

## Following delivery order

| Milestone | Outcome |
| --- | --- |
| Challenge track | Three-minute offline companion/focus story, accepted playground destination, physical-sensor compatibility, local resources under edition size limit. Reference screenshots and network integrations stay outside its package. |
| Before S4 | Roomier island, tile launcher, reference-density AI cards, horizontal timers, menu subpages/avatar switching, and core audio controls implemented. Real Mac audio/interaction acceptance pending. |
| S4 | System monitor, keep awake, audio device priorities/shortcuts and power/display essentials. Expand and validate the audio foundation. |
| S5 | Calendar repair/reminders, notifications, selected-folder downloads, clipboard/shelf and core capture tools. |
| S6 | Windows/Dock, keyboard and mouse modules, reversible preference changes and conflict handling. |
| S7 | Maintenance, package/app updates, media/recording, advanced process/network/fan tools; module-specific verification. |

## Complete reference coverage — 77 modules

Catalog: the 77 utility requirements retained from the supplied screenshots and catalog review. The screenshots show 73 installed-version modules; the current catalog adds four. Every entry below is retained, including advanced modules. A milestone is sequencing, not a delivery date.

Status: **Partial** = a related implemented slice with remaining acceptance/scope. **Planned** = backlog. Stable identifiers keep the requirements traceable; runtime implementations are Sieghart's own.

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
| `mixer` | Per-app volume mixer | Implemented core; Mac acceptance pending | Before S4 / S4 |
| `soundOutputSwitcher` | Output switcher | Device picker implemented; global shortcut pending | Before S4 / S4 |
| `audioPriority` | Preferred audio devices | Planned | S4 |
| `micMute` | Global microphone mute | Supported hardware mute implemented; global shortcut pending | Before S4 / S4 |
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
| `quickLauncher` | Quick tool panel | Partial — Seven widget routes with selected companion artwork; customizable launch panel pending | S5–S7 |
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
| `notchTimer` | Countdown, stopwatch and Pomodoro | Partial — Countdown, stopwatch and Pomodoro implemented; real Mac acceptance pending | S3 + S5 |
| `notchAccessories` | Accessory status and battery alerts | Planned | S3–S5 |
| `notchLyrics` | Lyrics | Planned | S3–S5 |
| `notchQueue` | Playback queue | Planned | S3–S5 |
| `notchLiveEqualizer` | Live audio bars | Planned | S3–S5 |
| `notchDownloads` | Selected-folder downloads | Planned | S3–S5 |
| `notchAgents` | AI limits/tokens/cost/live work | Partial — Live work, Codex quotas, charts, automatic price/FX estimates implemented; broader adapters/acceptance pending | S3 + S5 |
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
- Display behavior: click-only expansion, visual hover feedback, universal pointer-exit collapse, Small/Medium/Large expanded size, physical-notch geometry, capsule on other screens, multiple displays, full-screen and Spaces, lock/unlock, sensible hit targets, pure black compact backplate, no focus theft.
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

- [39 original screenshot gallery](Sieghart/Design/References/Widget/README.md), with timestamp/hash manifest.
- [Current character artwork](Sieghart/Design/Concepts/avatar-reactions.md) and [app notes](Sieghart/README.md).
- [October 6 regression captures](Sieghart/Design/References/Sieghart/README.md).
- [Known bugs](Sieghart/BUGS.md).
- Reference source is GPL-3.0-or-later; no upstream runtime code was copied into this MIT repository. Symbols carry their own [MIT attribution](Sieghart/THIRD_PARTY_NOTICES.md).
