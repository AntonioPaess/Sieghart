# Sieghart

Native macOS SwiftUI companion with a configurable notch widget and local Pomodoro timer.

The **Swift Student Challenge** is the primary product goal. This `.xcodeproj` is the macOS development base. The [repository overview](../README.md#swift-student-challenge) records the offline, three-minute experience and the separate submission milestone. Real accelerometer interaction remains a Challenge goal; compatibility with the accepted playground destination is still unverified.

## App and widget

The main window follows the approved [medium fidelity prototype](Design/Prototype/index.html): a dark sidebar with Overview, Focus, Activation, and Appearance. Overview shows the current timer and completed-session count. Focus opens the widget configuration.

Choose the focus duration **inside the widget** using the 5–60 minute ruler and slider. The same surface contains short breaks (5/10/15 minutes), long breaks (15/20/30 minutes), rounds (2/4/6/8 sessions), and automatic break start. Editing keeps the existing timer running until **Start new focus** replaces it. Back discards the draft settings. Starting saves the configuration locally.

Normal reveal opens the animated companion. Click the avatar for a happy reaction; it follows the pointer with restrained movement. Focus, voice, preferences, and hide remain in a small control row. A running timer is accessible through its time badge; a completed focus offers a separate Break action. Completion no longer replaces the companion home. The active timer tool has a small character, remaining time, progress, pause/resume, finish, adjust, and hide. Its top is a continuous opaque black surface aligned with the physical camera cutout; only the bottom corners are rounded. Configuration expands the same panel to fit all controls. The hosting view does not impose the initial home size on later views, and native resizing happens before the opacity reveal so a partially resized window cannot crop the SwiftUI content. The active timer becomes compact again. Appearance preferences control compact mode, character motion, and reduced motion; macOS Reduce Motion is always respected.

A completed focus interval counts once. The configured long break follows the last round; breaks do not increase the completed-focus count. Natural focus completion starts a break when enabled. **Finish** shows completion with a manual break action. A break ends with a prompt to start focus. Timer deadlines, paused state, interval type, rounds, selected settings, and completed count survive relaunch. Expired timers finish once after relaunch and wait for the user to start the next interval.

## Activation

Choose the global **Control + Option + key** shortcut or turn it off. Registration failures appear in Activation. Hover can be disabled. Impact gestures are optional and off by default; enabling them activates the experimental accelerometer reader and exposes one/two/three-impact action mappings. Sensor availability depends on Mac hardware.

Voice requests microphone and speech-recognition access only after pressing **Speak**. Speech authorization and audio callbacks explicitly cross actor boundaries safely; permission callbacks are not assumed to run on the main queue. The signed app includes the Audio Input entitlement required by Hardened Runtime. It listens for up to ten seconds and shows the actual transcript in the widget and app. **Run command** confirms it before execution. Supported English commands include “start focus”, “resume”, “pause timer”, “show”, and “hide”. The microphone remains off while idle. This is a command interface; conversational AI and a wake word remain future work.

Calendar is temporarily removed from the experience: no Calendar mode, menu, action, or privacy prompt is exposed. `CalendarContext.swift` remains available for later repair. A saved Calendar impact mapping falls back to showing Sieghart.

## Verification

- Generic macOS build covers `arm64` and `x86_64`.
- Deterministic timer checks cover configuration, pause/resume, short/long breaks, rounds, automatic breaks, restoration, and completion counting. Run from the repository root:

```sh
xcrun swiftc -swift-version 6 Sieghart/Sieghart/AssistantCore.swift Sieghart/Sieghart/SensorEngine.swift Sieghart/Tests/PomodoroChecks.swift -o /tmp/sieghart-pomodoro-checks
/tmp/sieghart-pomodoro-checks
```

Background speech-authorization checks exercise the actual callback bridge without requesting access or recording:

```sh
xcrun swiftc -swift-version 6 Sieghart/Sieghart/VoiceCallbacks.swift Sieghart/Tests/VoiceCallbackChecks.swift -o /tmp/sieghart-voice-callback-checks
/tmp/sieghart-voice-callback-checks
```

These checks do not start the sensor, microphone, or app UI. Display fit on the physical notch, global shortcut, impact hardware, and speech permissions still require a user test on the Mac.
