# Sieghart

Native macOS SwiftUI companion with a configurable notch island and local Pomodoro timer.

The **Swift Student Challenge** is the primary product goal. The `.xcodeproj` is the macOS development base. The [repository overview](../README.md#swift-student-challenge) records the offline, three-minute story and submission milestone. Real sensor interaction remains a goal; compatibility with the accepted playground destination needs validation.

## App and notch

- **Overview** shows the current session and completed count.
- **Focus** opens a dedicated tab in the app. It uses the same configuration editor as the widget: focus 5–60 minutes, short breaks 5/10/15, long breaks 15/20/30, rounds 2/4/6/8, and automatic breaks. Draft changes apply when starting a new session.
- **Activation** records separate companion and voice shortcuts, controls hover, and exposes optional impact mappings.
- **Appearance** controls expanded timer density, character motion, and reduced motion. macOS Reduce Motion is always respected.

Normal reveal opens the interactive CRT avatar. Phosphor eyes blink smoothly, its body floats gently, and pupils follow the pointer. Touch produces a happy expression and sparkle. Custom interactions preserve keyboard and VoiceOver actions with a rounded focus indicator, avoiding the native rectangular mouse focus ring.

Starting a session tucks the widget into a small island. The character and countdown sit beside the physical camera cutout, leaving the camera area clear. Hover or click expands timer controls; leaving or closing the controls returns to the island. Impact reveal also opens the companion from the compact state. Native panel bounds are controlled explicitly; the hosting view cannot retain an earlier view’s size constraints.

Every completed interval emits a separate completion event. The widget expands with a joyful avatar and a clear message, including when a break starts automatically. After five seconds it tucks away if the pointer is outside; hovering keeps the message available. The break countdown continues during this announcement. Manual Finish offers a break action. Completed breaks invite the next focus session.

Timer deadlines, paused state, interval type, configuration, rounds, and completed count survive relaunch. Focus counts once; breaks never increase that count. Long breaks follow the last round. Expired sessions finish once after relaunch and wait for the user before starting another interval.

## Shortcuts and voice

The companion defaults to **Control + Option + S**. Voice defaults to **Option + Command**, pressed and released. Record any key combination in Activation; modifier-only chords are saved on release. Escape cancels recording. Bindings persist independently, can be disabled, and cannot use the same chord. Existing companion shortcut choices migrate automatically.

Regular key combinations use Carbon hotkeys. Modifier-only shortcuts use local and global AppKit event monitors and require Accessibility permission for use outside Sieghart. Activation offers the permission button and displays availability. Using a regular key or an extra modifier suppresses a modifier-only trigger. No keyboard text is recorded or logged.

Voice starts explicitly through its shortcut, Speak, or the microphone button. Choose English or Portuguese. The app requests microphone and speech access, listens for up to ten seconds, and automatically executes a supported local command after recognition ends or a short pause. Capture stops before executing. Cancel remains available; the microphone is off while idle.

Supported intents include starting focus with a valid duration, pause, resume, finish, reset, start break, show, hide, and configuration. Negation, conflicting actions, and unsupported durations are rejected. This is a bounded local command interface; open-ended conversation remains future work. On-device speech is preferred when supported, but language and system availability can require Apple services. The timer and core interaction work independently of speech.

Speech authorization uses a Sendable callback bridge. Audio tap writes are serialized through a thread-safe feed that closes on teardown. Recognition results cross to the main actor as primitive text and status values. The signed target retains its Hardened Runtime Audio Input entitlement.

Impact gestures are off by default. Enabling them activates the experimental accelerometer reader and configurable one/two/three-impact mappings. Availability depends on Mac hardware.

Calendar is temporarily hidden. `CalendarContext.swift` remains for later repair; saved Calendar impact mappings fall back to revealing the companion.

## Verification

From the repository root:

```sh
bash Sieghart/Tests/run-checks.sh
```

The checks cover timer behavior and restoration, background speech callbacks, actual voice-command execution, shortcut persistence and modifier gestures, compact presentation, expanded-control collapse, and completion announcements during automatic breaks. They use isolated preferences and a headless controller: no app windows, sensor, microphone, permission requests, or system shortcut registration.

The generic signed macOS build covers `arm64` and `x86_64`. Physical notch fit, recording a shortcut in the UI, permissions, real microphone recognition, animation feel, and impact hardware still require a user run on the Mac.
