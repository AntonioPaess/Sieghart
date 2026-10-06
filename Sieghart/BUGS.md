# Sieghart bug tracker

## SG-001 — Shortcut intermittently stops responding

**Priority:** high. **Reported:** October 5, 2026. **Status:** recovery improvements implemented; the reported intermittent case remains open for validation on the Mac.

**Observed:** both the companion and voice shortcuts sometimes stop working and do not recover, confirmed by the user. The user confirmed switching desktops/Spaces and entering full-screen on the same Mac as a trigger. The investigation prioritizes shared capture/registration state and overlay visibility; a modifier-monitor-only interruption would not explain the default regular-key companion binding by itself.

### Analysis

- Recording a shortcut intentionally unregisters activation. Leaving the recorder previously did not clear its shared recording state, so every shortcut could remain blocked. This path is addressed by cancelling abandoned recording and restoring activation.
- Registrations previously refreshed only when Sieghart became active. Recovery now also follows foreground-app changes, Space changes, wake, display wake, and session unlock.
- Modifier-only gestures can retain a partial chord if a release is missed. Recovery clears that state; a lightweight health check also resets it when all modifiers are physically released.
- Accessibility permission changes and failed monitor/registration setup now trigger automatic retries. Status text identifies an unavailable monitor or secure keyboard input.
- Secure keyboard input is a possible external interruption for event monitoring; its involvement in this report is unconfirmed. The app observes its state and refreshes registration when it changes, without disabling that protection. See the installed macOS SDK’s `CarbonEventsCore.h`, and [Apple’s event-monitor documentation](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) for the global-monitor permission requirement.

### Verified

Headless regression checks cover activation being blocked during recording, cancelling only the relevant recorder, restoring the companion shortcut after abandonment, preserving configured bindings during recovery, and posting a Space-change notification through the actual recovery observer. Activation also shows the last received shortcut and offers Restore shortcuts, allowing a user run to distinguish event delivery from panel visibility. These checks do not install global shortcuts or change permissions.

### Remaining validation

Use each configured shortcut before and after leaving an unfinished recorder, switching apps and full-screen Spaces, locking/unlocking, and sleep/wake. If it stops again, record which binding failed, the foreground app, and the status shown in Activation. Confirm both regular-key and modifier-only bindings recover. Keep this issue open until the reported failure is reproduced or the recovery is confirmed on the Mac.
