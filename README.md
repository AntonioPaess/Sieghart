# Sieghart

### Your Mac companion, right at the notch.

[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](Sieghart/Sieghart.xcodeproj)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF?logo=apple&logoColor=white)](Sieghart/Sieghart)
[![macOS 14.6+](https://img.shields.io/badge/macOS-14.6%2B-222222?logo=apple&logoColor=white)](Sieghart/README.md)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Sieghart is a native macOS companion that lives near the camera notch. An animated avatar reacts to your touch and pointer, while focus sessions and quick controls stay close to the top of your screen.

Configure your Pomodoro **inside the widget**, choose how to bring Sieghart into view, and keep the main window for your overview and preferences.

> **In development.** The app compiles and its timer and speech-callback checks pass. Physical notch layout, microphone permissions, and hardware gestures are being validated on the Mac. Conversational AI is planned.

## The experience

| Feature | What it does |
| --- | --- |
| **Interactive companion** | Opens on the avatar, with blinking, breathing, pointer movement, and a reaction when clicked. |
| **Focus from the widget** | Choose 5–60 minutes, short and long breaks, rounds, and automatic break start in one surface. |
| **Compact timer** | Remaining time, progress, pause/resume, finish, and adjustments during a session. |
| **Persistent sessions** | Restores running deadlines, paused timers, completed sessions, and focus preferences after relaunch. |
| **Configurable activation** | A global Control + Option shortcut, optional hover, and configurable impact gestures. |
| **Voice on demand** | Press to speak, review the transcript, then confirm the command. |
| **Motion preferences** | Choose compact mode and character motion; macOS Reduce Motion is always respected. |

### Design reference

![Sieghart main-window design reference](Sieghart/Design/Prototype/app-preview.png)

*Medium fidelity prototype of the main window. This image is a design reference, not a capture of the running app. The native widget has since been updated to open on the interactive avatar.*

[Explore the design prototype](Sieghart/Design/Prototype) · [Read the implementation notes](Sieghart/README.md)

## Get started

### Requirements

- macOS **14.6 or later**.
- Xcode with a **Swift 6** compiler.
- Microphone and speech-recognition permission for voice commands.
- Compatible accelerometer hardware for the optional impact gestures.

The target builds for Apple silicon and Intel. Sensor availability depends on the Mac; keyboard and hover activation are available independently.

### Run in Xcode

```sh
git clone https://github.com/AntonioPaess/Sieghart.git
cd Sieghart
open Sieghart/Sieghart.xcodeproj
```

Select the **Sieghart** scheme and **My Mac**, then run. Configure signing if Xcode requests it. The project includes the microphone usage descriptions and Audio Input entitlement.

### Start your first session

1. Hover at the notch or press **Control + Option + S** to reveal the companion.
2. Click **Focus** and choose your duration, break lengths, and rounds.
3. Press **Start focus**. Use the timer controls to pause, resume, or finish.
4. Open **Activation** or **Appearance** in the main window to customize the experience.

The menu-bar menu also provides access to the widget and app. The shortcut key can be changed or disabled. Impact gestures are off by default.

## Voice and local data

Voice starts only after pressing **Speak** or the widget’s microphone button. It listens for up to ten seconds, shows the transcript, and waits for **Run command** before acting. Try “start focus”, “resume”, “pause timer”, “show”, or “hide”. Commands currently use English speech recognition.

Timers and preferences are stored locally in `UserDefaults`. The microphone is off while idle. Speech recognition uses Apple’s Speech framework; service availability and on-device processing depend on the language and system. See [Apple’s Speech documentation](https://developer.apple.com/documentation/speech/sfspeechrecognizer).

## Build and checks

Compile without launching the app:

```sh
xcodebuild \
  -project Sieghart/Sieghart.xcodeproj \
  -scheme Sieghart \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the deterministic timer checks:

```sh
xcrun swiftc -swift-version 6 \
  Sieghart/Sieghart/AssistantCore.swift \
  Sieghart/Sieghart/SensorEngine.swift \
  Sieghart/Tests/PomodoroChecks.swift \
  -o /tmp/sieghart-pomodoro-checks
/tmp/sieghart-pomodoro-checks
```

Run the background speech-callback checks:

```sh
xcrun swiftc -swift-version 6 \
  Sieghart/Sieghart/VoiceCallbacks.swift \
  Sieghart/Tests/VoiceCallbackChecks.swift \
  -o /tmp/sieghart-voice-callback-checks
/tmp/sieghart-voice-callback-checks
```

These checks do not open the app, activate the sensor, request permissions, or record audio. They cover timer configuration, pause/resume, short and long breaks, rounds, restoration, completion counting, and speech authorization arriving from a background queue.

## Project map

| Location | Responsibility |
| --- | --- |
| [`SieghartApp.swift`](Sieghart/Sieghart/SieghartApp.swift) | Main window, navigation, preferences, and menu-bar controls. |
| [`NotchWidget.swift`](Sieghart/Sieghart/NotchWidget.swift) | Notch panel, companion, focus configuration, and timer views. |
| [`AssistantCore.swift`](Sieghart/Sieghart/AssistantCore.swift) | Pomodoro intervals, deadlines, rounds, and persistence. |
| [`ActivationCore.swift`](Sieghart/Sieghart/ActivationCore.swift) | Global keyboard shortcut and explicit voice commands. |
| [`VoiceCallbacks.swift`](Sieghart/Sieghart/VoiceCallbacks.swift) | Safe speech-authorization callback bridge. |
| [`DesignSystem.swift`](Sieghart/Sieghart/DesignSystem.swift) | Shared palette, avatar, controls, and appearance preferences. |
| [`SensorEngine.swift`](Sieghart/Sieghart/SensorEngine.swift) / [`ImpactGestures.swift`](Sieghart/Sieghart/ImpactGestures.swift) | Experimental accelerometer input and configurable gesture actions. |
| [`Tests`](Sieghart/Tests) / [`Design`](Sieghart/Design/Prototype) | Deterministic checks and the design reference. |

## Next steps

- Validate the new widget layout and voice flow on the physical Mac.
- Improve the companion’s expressions and interactions.
- Restore Calendar after its data and permission flow are repaired; Calendar is currently hidden.
- Add reminders and conversational AI.

## License

Sieghart is released under the [MIT License](LICENSE).
