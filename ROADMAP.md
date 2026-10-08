# Sieghart roadmap

Updated October 8, 2026. This is the current execution plan; older Obsidian checkpoints remain historical. The user authorizes reference-level functional coverage with better usability and an integrated companion. Core Mac utilities take priority over additional integrations. Swift Student Challenge remains the first delivery; the complete Mac utility product continues afterward.

## Status and release gates

- **Sprint 1:** foundation, timer persistence and notch geometry delivered; visual iteration continued in Sprint 2.
- **Sprint 2:** published as `db2ea4f` — implementation closeout: six companions, nine poses, repeated-touch moods, focus configuration, compact island, celebration, voice acknowledgement, shortcut recovery, tools entry, Codex quotas, local token counters and separate spending ledger. Build/headless checks are evidence of implementation, not real-Mac acceptance.
- **Sprint 3:** complete and accepted October 8, 2026; the user reported all manual tests passed. Six-avatar onboarding, local AI consent/monitoring, dashboard/charts, automatic prices/FX, installed-app voice launch, browser search, charge CSV/JSON import/export, broader archived history and automatic Claude desktop quota reading are delivered. Appearance is configurable; voice lives in Companion. See [closeout and acceptance](Sieghart/Design/sprint-3-closeout.md).
- **Mac acceptance:** the user confirmed “Todos passaram” after receiving the test instructions. SG-001 through SG-005 are resolved on that report; no Sprint 3 blocker remains reported. The assistant keeps the app closed during its work. CLI builds, isolated checks, offscreen rendering and read-only adapter checks remain allowed. The previous Sprint 4 slice/editor is accepted; the newly delivered utilities and expanded greeting need separate physical acceptance.
- **Calendar:** hidden at the user's request; repair and reintroduction in S5, not a current release gate.
- **Costs:** recorded charges are actual user-entered expenses; token prices produce estimates. Official model price tables and dated USD/BRL FX adapters are implemented and verified against live public responses. They calculate API-equivalent estimates. Dated CSV/JSON charge imports with review, stable-reference deduplication and export are implemented; direct billing-account connection is outside this adapter.

## Sprint 4 — Requested implementation delivered; new Mac acceptance pending, October 8, 2026

The user moved clipboard history and an optional three-finger middle click forward, requested configurable side buttons and a coordinated onboarding arrival, and reported a spending discrepancy. [Implementation and Mac checklist](Sieghart/Design/sprint-4-checkpoint.md).

### Delivered first slice

- Shared local Clipboard in app/menu/island; a default side button and global **Control + Option + C**. Search/filter, pins, previews, copy/paste fallback, pause, exclusions and delete/clear. Choose 5/10/20 copies and cleanup after chosen days, Mac shutdown or lid close. Local bounded storage; pins count toward the cap. Shutdown/lid cleanup includes pins. Direct paste uses explicit Accessibility access.
- A dedicated Dynamic Island visual editor follows the October 8 reference: central companion/island preview, six clickable/draggable surrounding slots, dashed + for empty positions, Layout presets and Small/Medium/Large cards below. Add/edit/remove and swap/move save immediately. Optional Glass remains configurable. [Editor details](Sieghart/Design/island-layout-editor.md).
- Three-step onboarding with native 60 Hz six-avatar arrival, symmetric pointer gaze, no black strip above the avatar, optional voice/direct-paste access preparation and a special widget reveal on Finish. Existing approved artwork, offline core and Reduce Motion remain.
- Optional three-finger tap generates middle mouse click; default off, explicit Accessibility, unsupported state, drag/long/more-finger rejection and teardown. Uses an undocumented Mac contact capability; must be omitted from future Challenge packaging. The user accepted the first slice on October 8; the assistant did not perform real trackpad tests.
- AI response usage records, response-ID deduplication, recorded Fast changes and initial bounded full-file scanning with retained earlier counters correct the previous spending data path. Cleaner spending typography and exact unpriced disclosure. Internal models without published prices remain unpriced; API value remains separate from paid charges.

### Sprint 4 utility delivery — October 8

The user accepted the previous slice and editor on October 8. The remaining requested implementation is delivered in app/menu/island, with original center/drop/wave/dock launch and onboarding choreography. [Changes, capability boundaries and new Mac checks](Sieghart/Design/sprint-4-utilities.md).

- [x] User acceptance: clipboard/cleanup/paste/full-screen shortcut, rails/editor, three-finger taps, onboarding/gaze and spending first slice.
- [x] Base system monitor: CPU, exposed GPU, memory/pressure/cache/compression/swap, physical network rates/totals/IP, disks/capacity/exposed I/O, battery draw/health/time/cycles and USB names.
- [x] Keep awake: duration/deadline/conditions, owned assertions, supported lid boundary and opt-in valid-session restoration.
- [x] Audio priorities, actual-app favorites/order, optional global output/microphone shortcuts and route recovery.
- [x] Compatible brightness/software dimming/display sleep, HDR capability disclosure, optional Bluetooth sleep restoration and playback-key Music launch guard.
- [x] Utility-linked companion reactions, center greeting, presentation-size interruption continuity, configurable motion and reduced-motion fallback; twelve isolated groups and offscreen production previews.
- [ ] New physical Mac acceptance of these utilities and the expanded greeting. The earlier all-passed report is not used as evidence for later changes.

Numeric temperatures/fan control, XDR desktop boost, per-process network/speed testing and SMART remain explicit extended hardware backlog, not claimed delivered. Sprint 3 stays closed. Upload/email, connected chats, task agents and optional GitHub follow the core utility release gate.

### October 8 — Voice/search regressions and feature organization

- [x] Physical source/Xcode hierarchy organized as `Features/<Feature>/Views` and `ViewModels`, `Core/Services` and `Helpers`, and reusable `Shared/Components`, `Models`, `Services` and `Resources`. Native adapters are separated from observable feature state; navigation/onboarding/layout state has explicit ViewModels. See [architecture](Sieghart/ARCHITECTURE.md).
- [x] Evening correction after the user reproduced endless Listening: calibrate raised microphone noise and detect the trailing speech-envelope drop; end request audio and explicitly finish the recognition task. Authoritative final results end capture immediately. Expanded Companion stays visible throughout permission preparation/listening/finalization, superseding compact-while-listening. Unit and capture-to-command integration checks cover final words, exactly-once actions, stale/cancelled callbacks and pinned visibility. Physical speech acceptance remains open.
- [x] Google default-browser search supports broader Portuguese/English phrasing and general questions, preserving literal query contents and preventing invalid searches from triggering other actions.
- [x] Voice renews its input engine per command and handles headset format changes with one bounded retry before detected speech. Real AirPods acceptance remains pending.
- [ ] User Mac acceptance of the new voice/search/AirPods fixes: [exact regression checklist](Sieghart/Design/voice-search-regression-checks.md). This supplements the pending new utility/greeting acceptance above; prior Sprint 3 acceptance stays recorded.
- [ ] Challenge onboarding storytelling and a timed three-minute judging path. The user will write the story; [experience brief](Sieghart/Design/challenge-onboarding-brief.md) records goals, accessible/offline equivalents and a proposed time budget. The final storyline/judging flow is not implemented yet.

### October 8 — Free topic search and expressive voice

- [x] Search request grammar supports questions and direct topics; no topic whitelist. Exact reported phrases “pesquise por arquiteturas de mac” and “pesquisa github” are covered by capture-to-command integration.
- [x] Missing-final search recovery after ended audio and a stable transcription, with bounded drain and last-word/cancellation guards. App/timer actions retain strict final-result gating. Physical search acceptance remains open on the user's renewed report.
- [x] Real voice/action phases drive expectant preparation, listening ear/tilt, processing dots/gaze, successful hop/turn/landing and failure shake in all six native avatars. Interrupted transitions retain the visible pose; reduced/disabled motion keeps static cues. [Production animation preview](Sieghart/Design/Concepts/simple-companions-voice.gif).
- [ ] User verifies topic searches and expressive motion with Mac microphone/AirPods. Speaking/lip-sync, Megabrain, specialist delegation and role-specific file/email/calendar props remain planned.

## Sprint 3 — First-run companion and live AI

### Dated implementation record

The October 5–7 entries below retain the findings and pending checks as they stood at each checkpoint. The October 8 acceptance record supersedes those pending statuses.

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

### Window-close activation and companion quality — October 7, 2026

- The user clarified that “closed” means the red window-close button. A resident app delegate owns activation independently of the settings window and explicitly refuses last-window termination. Window-close/hide lifecycle recovery clears abandoned shortcut recording; Quit remains explicit termination. Isolated event tests cover both companion delivery routes after a simulated window close. Real window-close, voice and full-screen delivery remain SG-001 acceptance.
- The artwork previously rendered on a 42-point Canvas and scaled up. Every companion now draws at its final display size; only the small breathing/squash transform remains. Diffuse light, clipped edge shading, a recessed visor and a lit paper fold improve matte depth while retaining the approved silhouettes/palette and all motion/accessibility behavior.
- Main-window, island and menu production previews refreshed offscreen; the two latest avatar-quality photos are archived with hashes. Build, eight isolated groups and built-package checks passed without running the app or hardware.

### Optional appearance, Companion voice and renewed shortcuts — October 7, 2026

- System / Light / Dark apply to app, onboarding, menu, sheets and expanded island. Two independent persisted Glass switches, Other windows and panels / Dynamic Island, default off. The compact camera band stays black; Reduce Transparency overrides both. Adaptive text and stronger light-theme status contrast are implemented.
- Voice preparation, listening, transcript and acknowledgement/error now use Companion. The separate Voice page and launcher tile are removed; Cancel/Back stays in Companion without starting focus. Existing bounded geometry is retained.
- Renewed SG-001: system-dispatcher hotkeys start after AppKit launch; the resident app sets accessory policy. Default voice is Control + Option + V, requiring no monitoring grant; saved custom modifier-only chords remain. Status distinguishes registration from foreground-only monitoring, with a default-key option and received-backend detail. Delivery uses physical event timestamps and rejects duplicate backend callbacks even when their timestamps arrive in reverse order. Foreground full-display bounds select a higher overlay level; session lock/sleep removes both panels. Apple DTS guidance informs visibility, but real input/window-close/full-screen acceptance remains open.
- Eight isolated groups, universal signed build, package checks and offscreen production previews verify implementation. No app/Xcode window, real shortcut, microphone, sensor or audio capture is started by these checks. The new appearance reference is archived with its SHA-256 digest.
- Concrete future companion options and dependencies are recorded in [Useful companions](Sieghart/Design/companion-capabilities.md). Task handoff and contextual quick actions are the recommended first combination after core utilities; no speculative integration is enabled.

### Implementation closeout — October 7, 2026

- Voice search in English/Portuguese opens an encoded DuckDuckGo query in the default browser through NSWorkspace. Query words are data, never executable commands. Cancellation/generation checks and injected test actions keep execution/feedback coherent in Companion.
- Actual charge import/export: versioned JSON and UTF-8 CSV, downloadable template, review with provider/currency totals, exact Decimal values, reference/source provenance, atomic validation, conflict detection and duplicate protection including exported manual charges. No automatic invoice charge is fabricated from token estimates.
- **Expand history** reads up to a year of available Codex sessions/archives and Claude projects. It uses bounded files/bytes/counters, keeps metadata in memory for subsequent polling, permits cancellation and deduplicates cloned sessions/streamed messages. Coverage stays labeled partial; it does not claim account lifetime completeness or persist conversation content.
- Claude desktop plan-history versions 1/2 supply automatic percentages, including scoped Opus/Sonnet allowances when present. Only the latest self-contained reading is used; older than 30 minutes is unavailable. No credential is read and no renewal date is inferred. Dated manual reports remain a fallback.
- Audio permission preparation uses an unmuted temporary global tap rather than an empty process inclusion list. Output format/UID/channel changes rebuild routes even when the device ID is unchanged; restarted helpers can recover failed routes. Permission settings remain available while the mixer is enabled.
- Verification: all nine isolated groups pass; signed universal build/package checks pass; updated production screens render offscreen. Real read-only source check: Codex quota available, 80 local files / 852 counter records / zero missing models. No fresh Claude desktop plan history is available on this Mac; its missing-source state and both supported formats are verified.

### Mac acceptance — passed October 8, 2026

The user reported all checks passed. The original checklist is retained below; this is user-reported acceptance, not assistant-observed hardware verification.

1. **Interaction / SG-001, SG-002, SG-005:** single-click entire compact notch and close/crossing behavior; Control + Option + S / V after red window-close, across desktops and another app in full screen; correct placement without the bright top seam. Saved custom modifier-only chords require their separate monitoring grant.
2. **Voice:** actual microphone/speech grant and recognition, open an installed app, open a browser query, cancel and deny permission. Voice feedback must remain in Companion; focus starts only on request.
3. **Audio / SG-004:** actual capture grant/denial/retry, master plus up to five real apps, WhatsApp/media gain and mute, speakers/AirPods, headset call format changes, unplug/reconnect and mixer disable restoring normal playback.
4. **First run / AI / appearance:** save one of six avatars, accept/decline local monitoring, verify current provider and chart details against source, verify System/Light/Dark and independent Glass switches, reduced motion/transparency. Claude absence should stay unavailable; if used, enable its desktop usage menu and verify a fresh reading.

**Exit:** Sprint 3 is complete and accepted on October 8 following the user’s all-passed report. SG-001 through SG-005 are resolved; no Sprint 3 acceptance gate remains open. The last implementation check found no fresh Claude history, so absence remains unavailable. Sprint 4 has not started. Calendar remains hidden until S5.

## Following delivery order

| Milestone | Outcome |
| --- | --- |
| Challenge track | Three-minute offline companion/focus story, accepted playground destination, physical-sensor compatibility, local resources under edition size limit. Reference screenshots and network integrations stay outside its package. |
| Before S4 | Roomier island, tile launcher, reference-density AI cards, horizontal timers, menu subpages/avatar switching, and core audio controls implemented. User Mac acceptance passed October 8. |
| S4 | Requested base implementation delivered; previous slice/editor accepted. New utility/greeting physical checks remain. Extended hardware capabilities are tracked separately. |
| S5 | Calendar repair/reminders, notifications, selected-folder downloads, file shelf and core capture tools. Clipboard history moved to S4. |
| S6 | Windows/Dock, keyboard and mouse modules, reversible preference changes and conflict handling. |
| S7 | Maintenance, package/app updates, media/recording, advanced process/network/fan tools; module-specific verification. |

## Companion usefulness after core utilities

This is a future product direction, not an active integration sprint. First deliver and validate the utility sequence above. The user requested concrete differentiating options: [Useful companions](Sieghart/Design/companion-capabilities.md) spells out each experience, its real event source and its dependencies. Prioritize task handoff plus contextual quick actions, then consider work-resume notes, meeting audio context and optional gentle routines.

| Future companion role | Behavior | Dependency |
| --- | --- | --- |
| Quiet context | Express focus/break progress, AI working/completed and download completion through small gestures and optional brief messages. | Real timer, AI and download events; no fabricated activity. |
| Quick actions | Companion entry to open an app, control audio, keep the Mac awake and revisit a completed task. | Verified utility actions and explicit user interaction. |
| Calm reminders | Optional break/reminder nudges with quiet hours and a dismiss action; never starts focus automatically. | Reminder module and notification preferences. |
| Optional GitHub | Selected-repository PR review requests and build results, with a direct link to the relevant item. Read-only first; opt-in and unavailable/offline states. | Core utilities complete, separate account consent and adapter. |

GitHub makes sense as project context for people who develop software. It is optional and does not replace the primary Mac utilities or the offline companion journey. No GitHub connection is implemented or enabled in this round.

### Task continuity and avatar agents — User proposal, October 7, 2026

- **Product intention:** build attachment through useful, reliable assistance, with less switching between apps and fewer steps to remember. Supporting people with ADHD is a user-defined design goal; clear task status, resumable steps, gentle reminders and no forced focus guide the experience.
- **File-to-outcome workflow:** receive a dropped/selected file, upload to a chosen connected service, prepare a recipient-specific email with the file/link, and send with explicit user authorization. Show actual progress, sharing destination and a final result; resume failures without duplicate uploads or sends. File handling, upload/email adapters, recipient resolution and task persistence are dependencies.
- **Avatar organization:** a user-chosen primary companion receives requests and presents results; other avatars may take configurable task-agent roles for files, communication, research, routines or development. Keep one coherent task status in Companion, with small agent indicators rather than separate chat pages. Any avatar can be the principal one; roles do not lock basic utilities to a character.
- **Attachment:** remembered user choices, a clear “where I stopped” state, useful next actions and expressive receiving/carrying/working/completion gestures. Reminders stay opt-in and avoid guilt or punitive streaks.
- **Sequence:** record as a future companion-workflow milestone after core utilities and verified adapters. This proposal does not add new Sprint 3 exit requirements. Network-dependent email/upload stays outside the mandatory offline Challenge story. No upload, email sending or agent delegation is implemented/enabled here.

Detailed experience and dependencies: [Useful companions](Sieghart/Design/companion-capabilities.md).

### New companion reference — October 8, 2026

The user supplied Coucou’s animated demo after accepting Sprint 3. [Reference study](Sieghart/Design/coucou-reference.md): task/result hierarchy, coordinated avatar/surface motion, file receive/carry gestures and small task-agent indicators. Use these for the future companion workflow while retaining the approved six-character family, click-only opening, pointer-exit collapse and configurable Glass. Core S4 utilities remain first; this research introduces no runtime integration or new Sprint 3 gate.

### Expressive specialists — User direction, October 8, 2026

- A chosen principal companion with up to five user-assigned specialists: email, agenda, expense/bill organization, wellbeing and knowledge/projects (Obsidian/GitHub). Any avatar can take any role; shared file tools stay available to all.
- Character-specific preparing/listening/interpreting/working/speaking/waiting/success/error animations. Explore a cupped/unfolding ear for actual listening and a hop/turn after verified completion. Understanding a request must remain distinct from finishing it.
- Optional break routines first; AirPods head-motion calibration and a separately authorized iPhone/Watch health-data bridge are feasibility work. Session time is not proof of sitting, and head tilt is not full-body posture.
- Configurable Obsidian/GitHub connectors, with MCP where supported, selected sources/actions and resumable multi-tool tasks.
- Local “Megabrain active” / “ativar Megabrain” Easter egg: temporary stylized giant brain and playful recovery, interruptible and reduced-motion compatible.

These are recorded requirements for a future companion milestone after core utilities, not shipped features or additional Sprint 4 acceptance gates. No agent runtime, health connection, MCP connection or Easter egg is implemented in this documentation update. [Roles, motion states, feasibility and acceptance](Sieghart/Design/companion-capabilities.md).

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
| `middleClick` | Three-finger middle click | Implemented optional tap; Accessibility and supported trackpad required; user accepted October 8 | S4 (Mac only) |
| `mouseClickDebounce` | Mouse click debounce | Planned | S6 |
| `keyboardDebounce` | Keyboard debounce | Planned | S6 |
| `textSnippets` | Text expansion snippets | Planned | S6 |
| `superKey` | Hyper key | Planned | S6 |
| `quitWindowProtection` | Quit/close protection | Planned | S6 |

### Clipboard and files (7)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `clipboardHistory` | Local clipboard history | Implemented — local text/images/files, 5/10/20, cleanup, search/pins, direct paste fallback; user accepted October 8 | S4 |
| `pastePlain` | Paste plain text | Planned | S5 |
| `finderCutPaste` | Finder cut and paste | Planned | S5 |
| `finderRename` | Rename shortcut | Planned | S5 |
| `shelf` | Temporary file shelf | Planned | S5 |
| `urlCleaner` | Remove URL tracking | Planned | S5 |
| `diskImageInstaller` | Disk image app installer | Planned | S5 |

### Sound (5)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `mixer` | Per-app volume mixer | Implemented core; earlier Mac acceptance passed; saved favorites/order delivered, new checks pending | Before S4 / S4 |
| `soundOutputSwitcher` | Output switcher | Implemented — picker plus optional global cycle shortcut; new shortcut check pending | Before S4 / S4 |
| `audioPriority` | Preferred audio devices | Implemented — saved UID priorities; opt-in device selection on connection changes; new hardware checks pending | S4 |
| `micMute` | Global microphone mute | Implemented — supported selected-input mute plus optional global shortcut; new check pending | Before S4 / S4 |
| `musicBlock` | Prevent Music auto-launch | Implemented — opt-in playback-key/new-launch window; Accessibility required; new check pending | S4 |

### Energy and displays (4)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `keepAwake` | Keep awake: duration/deadline/lid | Implemented — duration/deadline/conditions/owned assertions/restoration; standard lid rules | S4 |
| `brightness` | Per-display brightness/power | Implemented compatible native brightness, reversible gamma dimming and display sleep; new check pending | S4 |
| `extraBrightness` | XDR extra brightness | HDR headroom disclosed; XDR desktop boost remains extended hardware backlog | S4 |
| `bluetoothSleep` | Bluetooth on sleep | Implemented — owned device disconnect and asynchronous authenticated reconnection; new check pending | S4 |

### Tools (19)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `quickLauncher` | Quick tool panel | Partial — Shared clipboard route, avatar artwork and six customizable side slots; broader launcher pending | S5–S7 |
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
| `notchTimer` | Countdown, stopwatch and Pomodoro | Partial — Countdown, stopwatch and Pomodoro core implemented and user accepted; S5 extensions remain | S3 + S5 |
| `notchAccessories` | Accessory status and battery alerts | Planned | S3–S5 |
| `notchLyrics` | Lyrics | Planned | S3–S5 |
| `notchQueue` | Playback queue | Planned | S3–S5 |
| `notchLiveEqualizer` | Live audio bars | Planned | S3–S5 |
| `notchDownloads` | Selected-folder downloads | Planned | S3–S5 |
| `notchAgents` | AI limits/tokens/cost/live work | Partial — S3 live work, quota/history/import adapters, charts and price/FX estimates delivered and user accepted; broader S5 scope remains | S3 + S5 |
| `notchWatch` | Selected screen-area monitoring | Planned | S3–S5 |
| `notchMascot` | Companion interaction | Partial — Six original companions and reactions; feature-specific interactions expand per module | S3 + S5 |

### System monitor (8)

| Reference ID | Sieghart requirement | Status | Delivery |
| --- | --- | --- | --- |
| `monitorCPU` | CPU use and temperature | Base CPU deltas and thermal state implemented; numeric temperature remains hardware backlog | S4 |
| `monitorGPU` | GPU use and temperature | Exposed utilization implemented; numeric temperature remains hardware backlog | S4 |
| `monitorMemory` | Memory pressure/cache/compression/swap | Implemented used/pressure/cache/compression/swap detail | S4 |
| `monitorNetwork` | Traffic, apps, local IP and speed test | Physical traffic/totals/IP implemented; per-app traffic and speed test remain backlog | S4 |
| `monitorDisk` | Space, I/O, SMART and eject | Capacity/free/exposed I/O implemented; SMART/eject remain backlog | S4 |
| `monitorPower` | Battery/power/time/health/cycles | Implemented reported battery draw/time/health/cycles and source | S4 |
| `connectedDevices` | Connected peripherals | USB names and actual audio devices implemented; broader peripherals remain backlog | S4 |
| `fanControl` | Fan status and control | Unavailable in base monitor; RPM and manual/curve control remain extended hardware backlog | S4 |

## Foundations beyond the module count

- Onboarding: preset/individual module choices, six avatars, language, optional permissions tied to enabled features, no unnecessary access to finish. Revisit later from Settings.
- Settings: searchable sections, configurable keyboard/mouse shortcuts, startup at login, theme, menu-bar symbol/color, density, module enable/disable and real service teardown.
- Display behavior: click-only expansion, visual hover feedback, pointer-exit collapse outside busy voice, Small/Medium/Large expanded size, physical-notch geometry, capsule on other screens, multiple displays, full-screen and Spaces, lock/unlock, sensible hit targets, pure black compact backplate, no focus theft.
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
