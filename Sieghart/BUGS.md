# Sieghart bug tracker

## SG-001 — Shortcut intermittently stops responding

**Priority:** high. **Reported:** October 5, 2026. **Status:** recovery improvements and listen-only session event tap implemented; the reported intermittent case remains open for validation on the Mac.

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

The user again reported both shortcuts unavailable in full-screen apps on another Space. Healthy registrations now stay installed through foreground/Space transitions instead of being torn down on every event. Carbon handlers use the dispatcher target; existing permitted monitoring routes ordinary keys even after successful registration. A per-action delivery gate prevents two backends from toggling the same action twice. Both overlay panels declare full-screen auxiliary capability and preserve screen-edge frames, separating visibility recovery from input recovery. Explicit Restore shortcuts still rebuilds registration.

Headless checks exercise both backend orders, exact chord matching, repeated gestures and Space recovery without installing actual shortcuts or opening a window. Actual full-screen delivery remains unverified.

### Remaining validation

Use each configured shortcut before and after leaving an unfinished recorder, switching apps and full-screen Spaces, locking/unlocking, and sleep/wake. If it stops again, record which binding failed, the foreground app, and the status shown in Activation. Confirm both regular-key and modifier-only bindings recover. Keep this issue open until the reported failure is reproduced or the recovery is confirmed on the Mac.


## SG-002 — Island click remains unreliable

**Priority:** high. **Reported:** October 6, 2026. **Status:** native first-click and toggle corrections implemented; physical Mac acceptance pending.

The user reported that clicking still did not behave as expected. The previous activation handler always opened rather than toggled, queued its action asynchronously, used a nearly invisible window alpha, and did not explicitly accept first mouse when another app held focus. The native target covered only the camera gap rather than both compact wings. SwiftUI button labels did not explicitly cover transparent spacing.

The native strip now has a clear background with normal window opacity, spans the compact surface, synchronously toggles open/closed, and accepts first mouse. SwiftUI hosting also accepts first mouse, with rectangular compact label targets. Ordering keeps only the camera-height strip over the expanded panel. Hover still highlights only; leaving expanded content collapses it.

Offscreen checks dispatch mouse events through the real native handler, verify first-mouse acceptance, idle/AI/clock opening and second-click closure, and verify mouse-exit collapse while stopwatch time continues. No app window is launched by these checks. Confirm single click from another app, both wings, second activation-strip click, all three timer modes, Spaces/full-screen and pointer exit on the physical Mac before closing this issue.


### Whole-notch and approach follow-up — October 6

The user reported only lateral AI-island clicks working and controls disappearing while approaching them. Native activation now covers the complete current island header and treats its center as a hit, including the camera gap. A mouse-down fallback is restricted to the activation rectangle when another application receives that click. A visible-only pointer point check covers missing camera tracking. Borderless panels preserve their requested frames at the screen edge.

Pointer exit tolerance is now 800 ms; a keyboard reveal provides four seconds to reach the controls. Entry cancels pending collapse. Explicit close acts immediately, while timer completion keeps its announcement deadline. Isolated checks cover center/wing hit testing, AI and timer toggle routes, crossing cancellation and keyboard approach grace. Physical Mac clicks, full-screen placement and animation feel remain the acceptance gate.


## SG-003 — Compact island resembles a selected control

**Reported:** October 6, 2026, in IMG_6234.HEIC. **Status:** contour removed; offscreen hover render verified.

The blue/lilac edge was the SwiftUI hover stroke around the compact shell. That stroke is removed, and the native canvas hides its outline whenever compact or departing. Hover now uses a subtle happy companion expression in idle, AI and timer states. The camera band stays black; click and keyboard actions retain their existing routes. [Production hover preview](Design/Concepts/compact-hover-preview.png). Physical notch and full-screen behavior remain tracked in SG-001/SG-002.
