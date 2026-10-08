# Sieghart bug tracker

## Acceptance — October 8, 2026

After receiving the manual test instructions, the user reported “Todos passaram” (all passed). SG-001 through SG-005 are resolved on this report. The assistant did not run live shortcuts, microphone or audio tests. Investigation notes below preserve the earlier pending statuses as dated history; reopen the specific issue if a regression occurs. See [Sprint 3 accepted closeout](Design/sprint-3-closeout.md).

## SG-001 — Shortcut intermittently stops responding

**Priority:** high. **Reported:** October 5, 2026. **Status:** resolved — user confirmed all manual acceptance tests passed October 8, 2026.

**Observed:** both the companion and voice shortcuts sometimes stop working and do not recover, confirmed by the user. The user confirmed switching desktops/Spaces and entering full-screen on the same Mac as a trigger. The investigation prioritizes shared capture/registration state and overlay visibility; a modifier-monitor-only interruption would not explain the default regular-key companion binding by itself.

### Analysis

- Recording a shortcut intentionally unregisters activation. Leaving the recorder previously did not clear its shared recording state, so every shortcut could remain blocked. This path is addressed by cancelling abandoned recording and restoring activation.
- Registrations previously refreshed only when Sieghart became active. Recovery now also follows foreground-app changes, Space changes, wake, display wake, and session unlock.
- Modifier-only gestures can retain a partial chord if a release is missed. Recovery clears that state; a lightweight health check also resets it when all modifiers are physically released.
- Accessibility permission changes and failed monitor/registration setup now trigger automatic retries. Status text identifies an unavailable monitor or secure keyboard input.
- Secure keyboard input is a possible external interruption for event monitoring; its involvement in this report is unconfirmed. The app observes its state and refreshes registration when it changes, without disabling that protection. See the installed macOS SDK’s `CarbonEventsCore.h`, and [Apple’s event-monitor documentation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) for the global-monitor permission requirement.

### Verified

Headless regression checks cover activation being blocked during recording, cancelling only the relevant recorder, restoring the companion shortcut after abandonment, preserving configured bindings during recovery, and posting a Space-change notification through the actual recovery observer. Activation also shows the last received shortcut and offers Restore shortcuts, allowing a user run to distinguish event delivery from panel visibility. These checks do not install global shortcuts or change permissions.

### October 6 follow-up

The user also observed shortcuts only activating with Sieghart foreground. Modifier gestures now prefer a listen-only CG session tap when Input Monitoring is granted, with the existing Accessibility/AppKit path as fallback. Main-run-loop common modes and reenabling after tap interruption cover background/modal delivery. Failed regular Carbon registrations can use the permitted tap. Permission status is explicit; an ordinary key shortcut does not require monitoring access. Tests feed the same event router without registering real shortcuts. Cross-app and full-screen delivery remains an acceptance check, not a claimed hardware result.

### Renewed full-screen report — October 6

The user again reported both shortcuts unavailable in full-screen apps on another Space. Healthy registrations now stay installed through foreground/Space transitions instead of being torn down on every event. Carbon handlers initially used the dispatcher target; existing permitted monitoring routes ordinary keys even after successful registration. A per-action delivery gate prevents two backends from toggling the same action twice. Both overlay panels declare full-screen auxiliary capability and preserve screen-edge frames, separating visibility recovery from input recovery. Explicit Restore shortcuts still rebuilds registration.

Headless checks exercise both backend orders, exact chord matching, repeated gestures and Space recovery without installing actual shortcuts or opening a window. Actual full-screen delivery remains unverified.

### Remaining validation

Use each configured shortcut before and after leaving an unfinished recorder, switching apps and full-screen Spaces, locking/unlocking, and sleep/wake. If it stops again, record which binding failed, the foreground app, and the status shown in Activation. Confirm both regular-key and modifier-only bindings recover. Keep this issue open until the reported failure is reproduced or the recovery is confirmed on the Mac.

### Red window-close clarification — October 7

The user confirmed closing the main window with its red button, rather than Quit. `ResidentAppDelegate` now retains activation independently of that window and explicitly returns false for last-window termination. Closing/hiding a window cancels an abandoned recorder and checks shortcut recovery. The app stays resident; explicit Quit still stops it. Isolated checks post window-close notifications and route the companion through Carbon and monitor entry points without registering live shortcuts. The actual window-close/voice/full-screen case remains open until user acceptance. This is lifecycle hardening, not a proven reproduction of the physical failure.

[Apple's last-window lifecycle contract](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)).



### Renewed whole-Mac report — October 7

The user reports that global delivery is still not resolved after the previous lifecycle changes. No physical reproduction was performed. This round separates input setup from overlay visibility:

- Install/register on the system dispatcher after AppKit launch; the resident delegate sets accessory policy and owns activation after main-window close.
- Default voice changes to Control + Option + V, using a regular-key system hotkey without a keyboard-monitoring grant. Saved custom modifier-only chords remain intact; a default-key button is offered explicitly. Foreground-only/unavailable monitoring is shown accurately.
- Carbon, CG and AppKit delivery use event timestamps rather than queued callback arrival, with received source shown in Activation. Reverse timestamp delivery is also deduplicated, preventing a second backend from immediately closing the island. The CG callback queues work instead of running speech preparation in its callback.
- Both overlays choose the higher screen-saver window level while the foreground window bounds cover the notch display; normal desktop ordering uses statusBar + 1. Only window bounds metadata is examined, not screen pixels. Lock/session resignation and sleep stop voice and order out both panels. Space/app changes refresh ordering without reopening a dismissed page. This follows [Apple DTS's tested full-screen overlay setup](https://developer.apple.com/forums/thread/826308).

Tests cover default-key and saved modifier choices, simulated window-close delivery, deduplication, and fabricated full-display bounds/levels. They do not register physical shortcuts or test WindowServer delivery. User acceptance must confirm Control + Option + S and Control + Option + V after red window-close, in a different desktop and with another app full screen. Compare the Last received/backend status when diagnosing a remaining failure. If a saved modifier-only chord is retained, verify its grant/status separately. SG-001 remains open.


## SG-002 — Island click remains unreliable

**Priority:** high. **Reported:** October 6, 2026. **Status:** resolved — user confirmed all manual acceptance tests passed October 8, 2026.

The user reported that clicking still did not behave as expected. The previous activation handler always opened rather than toggled, queued its action asynchronously, used a nearly invisible window alpha, and did not explicitly accept first mouse when another app held focus. The native target covered only the camera gap rather than both compact wings. SwiftUI button labels did not explicitly cover transparent spacing.

The native strip now has a clear background with normal window opacity, spans the compact surface, synchronously toggles open/closed, and accepts first mouse. SwiftUI hosting also accepts first mouse, with rectangular compact label targets. Ordering keeps only the camera-height strip over the expanded panel. Hover still highlights only; leaving expanded content collapses it.

Offscreen checks dispatch mouse events through the real native handler, verify first-mouse acceptance, idle/AI/clock opening and second-click closure, and verify mouse-exit collapse while stopwatch time continues. No app window is launched by these checks. Confirm single click from another app, both wings, second activation-strip click, all three timer modes, Spaces/full-screen and pointer exit on the physical Mac before closing this issue.


### Whole-notch and approach follow-up — October 6

The user reported only lateral AI-island clicks working and controls disappearing while approaching them. Native activation now covers the complete current island header and treats its center as a hit, including the camera gap. A mouse-down fallback is restricted to the activation rectangle when another application receives that click. A visible-only pointer point check covers missing camera tracking. Borderless panels preserve their requested frames at the screen edge.

Pointer exit tolerance is now 800 ms; a keyboard reveal provides four seconds to reach the controls. Entry cancels pending collapse. Explicit close acts immediately, while timer completion keeps its announcement deadline. Isolated checks cover center/wing hit testing, AI and timer toggle routes, crossing cancellation and keyboard approach grace. Physical Mac clicks, full-screen placement and animation feel remain the acceptance gate.


## SG-003 — Compact island resembles a selected control

**Reported:** October 6, 2026, in IMG_6234.HEIC. **Status:** resolved — contour removed; user confirmed all manual acceptance tests passed October 8, 2026.

The blue/lilac edge was the SwiftUI hover stroke around the compact shell. That stroke is removed, and the native canvas hides its outline whenever compact or departing. Hover now uses a subtle happy companion expression in idle, AI and timer states. The camera band stays black; click and keyboard actions retain their existing routes. [Production hover preview](Design/Concepts/compact-hover-preview.png). Physical notch and full-screen behavior remain tracked in SG-001/SG-002.


## October 6 evening — SG-001/SG-003 follow-up

Both shortcuts were again reported unavailable in full-screen apps. The built app is now a menu-bar agent (`LSUIElement`) and Carbon uses its application event target. Existing Accessibility/Input Monitoring grants are accepted by the session tap; invalid tap ports trigger recovery. The physical full-screen case stays open. No real shortcuts were registered for verification.

The avatar's initial focus stroke is removed from custom interaction; the native hosting view provides an empty focus-ring mask. Keyboard navigation retains a soft surface cue. Physical first-click acceptance remains tied to SG-002.

## SG-004 — App mixer does not request permission / WhatsApp gain ineffective

**Reported:** October 6, 2026. **Status:** resolved — user confirmed all manual acceptance tests passed October 8, 2026.

The compiled Info.plist omitted the system-audio privacy description even though the project contained an INFOPLIST_KEY setting. Enable only flipped a Boolean and first tap creation could fail during rigid device-stream format checks before reaching the permission path. The explicit Info.plist is now merged into Debug/Release. A temporary unmuted tap-only aggregate starts the public permission flow on Enable, with request/failure/retry/settings state and cancellation protection. No saved gain applies before that succeeds.

Per-app routes now use stereo process mixdown across the app's output streams rather than one device stream. Drift compensation handles the aggregate clock; mono headset calls fold stereo samples without changing frame timing. Exact sample-rate equality and unnecessary hardware-input stream checks no longer block startup. The callback selects only the tap's trailing buffers, never hardware microphone buffers. Unity gain tears down the tap; failed replacement keeps the existing route. Public process bundle identity also resolves app helpers. Five actual running app rows maximum are selected with playing/connected apps first; waiting apps are disabled rather than showing an ineffective adjustment.

Mocked checks cover permission request, denial/retry/cancel, saved gain gating, no empty-process routing, five/two app counts, mono/stereo/planar buffer mapping, errors and teardown. The built signed universal bundle contains the audio privacy key. Actual first permission prompt, denial/recovery, WhatsApp voice/call volume, AirPods mode changes, devices disconnecting and latency must be confirmed on the Mac before closing this bug.

## SG-005 — Oversized menu, bright top seam, static sleep

**Reported:** October 6, 2026. **Status:** resolved — user confirmed all manual acceptance tests passed October 8, 2026.

Menu width decreased from 560 to 380 points; natural subpage heights replace the fixed content area. Companion height is about 297 versus 548 points. Compact child controls preserve navigation and timer actions. Native island positioning overlaps the screen edge by one backing pixel and removes the contour stroke that could expose the bright seam. Sleeping motion now visibly breathes/sways and floats a fading “z” for every avatar. Isolated motion checks cover all six and disabled/reduced-motion stillness. The production sleep GIF demonstrates the new movement; it is design documentation outside app resources.


## Sprint 3 implementation closeout — October 7, 2026

The user reconfirmed **keep the app closed; I will test**. Nine isolated groups, signed universal build/package checks and offscreen screens pass. Real read-only Codex quota/counter sources are available; no fresh Claude desktop plan history exists here. [Exact manual acceptance](Design/sprint-3-closeout.md) now lists the remaining checks. SG-001/SG-002/SG-004 remain open for those results, and SG-005's physical top seam remains unverified.

SG-004 follow-up: permission preparation now uses a temporary unmuted global tap, replacing an empty inclusion list that captures no processes. Same-ID output sample-rate/channel/UID changes tear down and rebuild routes. A restarted helper clears a previous failed-route suppression; disappearing audio processes release stale routes. Permission settings remain accessible after Enable, because startup success alone is not proof of audible gain control. Mock denial/retry/format-change cases pass; actual macOS permission and WhatsApp/AirPods playback have not been tested.

Voice search has a real encoded default-browser action, actual charges have a reviewed CSV/JSON import/export adapter, expanded history includes archives, and automatic Claude desktop percentages have validated versioned parsing/freshness. Those implementation items are complete; actual speech and file-picker interaction join the user acceptance pass.


## SG-006 — Voice finishes before the user stops speaking

**Reported:** October 8, 2026. **Status:** implementation verified with synthetic inputs; user speech acceptance pending.

Automatic island collapse also cancelled voice; it now keeps an explicitly started session alive with a compact microphone/status indicator, while explicit Cancel/Close still cancels. The original capture always ended after ten seconds, or 1.2 seconds after the last changed transcript, and cancelled recognition before final words could arrive. PCM activity now keeps capture alive; quiet ends audio and final recognition dispatches once. Cancellation, input loss and the session/final-result safety limits run no partial command. See [changes, bounds and Mac tests](Design/voice-search-regression-checks.md).

## SG-007 — Restricted search wording and wrong engine

**Reported:** October 8, 2026. **Status:** parser/URL and injected action checks passed; real voice/browser acceptance pending.

DuckDuckGo was hard-coded and colloquial Portuguese/general question forms were missing. Google now opens in the default browser, with broader explicit search phrases and questions. Accents/query content are preserved; invalid queries cannot fall through into timer/app commands. Existing local AI-limit questions keep their panel route.

## SG-008 — Voice does not listen with AirPods

**Reported:** October 8, 2026; the user clarified this is microphone voice capture, not app volume. **Status:** lifecycle/PCM fixes verified in isolation; physical AirPods reproduction/acceptance pending.

Capture previously reused one audio engine across input/device changes. Each command now creates a fresh engine, validates hardware/capture formats, observes engine configuration changes and permits one bounded preparation retry before detected speech. An interrupted spoken command is cancelled without dispatch; stale capture callbacks cannot affect a replacement. This addresses the identified lifecycle risk without claiming a confirmed physical diagnosis. Confirm the selected microphone in Audio → Microphone and perform the headset checklist above. [Apple's configuration-change contract](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange) describes hardware rate/channel changes stopping and uninitializing the engine.
