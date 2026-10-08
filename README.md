# Sieghart

### Your Mac companion, right at the notch.

[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](Sieghart/Sieghart.xcodeproj)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-007AFF?logo=apple&logoColor=white)](Sieghart/Sieghart)
[![macOS 14.6+](https://img.shields.io/badge/macOS-14.6%2B-222222?logo=apple&logoColor=white)](Sieghart/README.md)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Sieghart is a native macOS companion that lives near the camera notch. An animated avatar reacts to your touch and pointer, while focus sessions and quick controls stay close to the top of your screen.

Choose **Timer**, **Pomodoro** or **Stopwatch** in the app’s **Timers tab**, the menu-bar Timers subpage, or directly inside the widget. Starting is explicit; the compact island keeps the countdown or elapsed time nearby while you work.

**Built toward the Swift Student Challenge.** The goal is a short, personal experience about physical interaction, an expressive companion, and calmer focus. The macOS app is the development base; Challenge packaging and hardware compatibility remain milestones.

> **Sprint 4 implementation delivered.** The first slice passed the user’s Mac checklist; new utilities and greeting have separate physical checks. Connected email/upload workflows and extended hardware capabilities remain planned.

## October 8 — Voice/search and MVVM organization

Sources and Xcode groups now use **Features / Core / Shared**, with screen Views/ViewModels together by feature, native services/helpers in Core and reused controls/preferences/coordinators in Shared. [Architecture and boundaries](Sieghart/ARCHITECTURE.md).

Voice completion now explicitly finishes the recognition task after audio quiet, preserving final words and dispatching once. The evening regression exposed a noise-floor error and a missing task-finalization call. Expanded Companion stays visible during preparation, listening and finalization even with the mouse elsewhere. A new capture-to-command integration suite covers this lifecycle with simulated audio/recognition and injected launches. Search uses Google; fresh headset input and cancellation guards remain. [Changes and exact Mac checks](Sieghart/Design/voice-search-regression-checks.md). Actual speech/AirPods acceptance is still pending.

The user will provide onboarding storytelling. A [three-minute experience brief](Sieghart/Design/challenge-onboarding-brief.md) is recorded; the final judging flow is not yet delivered.

## Sprint 4 — System utilities and greeting

The previous clipboard/island/editor slice passed the user's Mac tests. The remaining requested implementation now adds System, Keep awake, audio favorites/order/device priorities and optional global output/microphone shortcuts, compatible brightness/dimming/display sleep, optional Bluetooth restoration and a narrow Music launch guard. The six companions greet from the center, wave and dock into the island; motion is optional and interruptions keep the current contour.

[Full implementation, new Mac checks and hardware boundaries](Sieghart/Design/sprint-4-utilities.md). New hardware acceptance is pending; XDR boost and temperature/fan control remain backlog.

![Six native companions greeting](Sieghart/Design/Concepts/companion-launch-greeting.gif)

## Sprint 4 — First slice

- **Clipboard:** local text, image and file-reference history; search, pins, preview, copy/paste, exclusions and pause. Choose **5, 10 or 20** saved copies and cleanup after chosen days, Mac shutdown or lid close. Open with **⌃⌥C**, the side button, app tab or menu subpage. Direct Paste needs Accessibility; Copy/⌘V works without it.
- **Side buttons:** Dynamic Island offers a visual island preview with six surrounding positions. Click to add/edit/remove, drag to move or swap, and choose Essentials/Focus/Work from Layout. Size cards and optional Glass sit below the editor.
- **Companion arrival:** Welcome → avatar → local tools, native fluid animation, balanced left/right gaze, optional permission setup and a distinct widget entrance on Finish. No black band above the avatar.
- **Optional middle click:** Activation → Three-finger middle click. Off by default; tap with three fingers, grant Accessibility and retry. Unsupported trackpads show unavailable. Future Challenge packaging must omit this Mac-only contact adapter.
- **AI spending:** response-record deduplication, Fast tier changes, first full bounded scan and retained counters from long files. Internal models without official prices remain explicitly unpriced. API-equivalent value is separate from paid charges.

![Six companions arriving](Sieghart/Design/Concepts/companion-welcome-motion.gif)

[Clipboard preview](Sieghart/Design/Concepts/island-clipboard-preview.png) · [onboarding](Sieghart/Design/Concepts/onboarding-welcome-preview.png) · [first-slice changes and accepted checklist](Sieghart/Design/sprint-4-checkpoint.md).

## The experience

| Feature | What it does |
| --- | --- |
| **Six companions** | CRT Buddy, Arcade 1984, Minimal Spirit, Coast Buddy, Paper Pal and Ink Buddy. Choose your companion during onboarding; change it later in Appearance or the menu-bar Avatars tab. It also becomes your menu-bar icon. |
| **Expressive reactions** | Touch brings a smile; repeated pokes make the companion grumpy, then sleepy. Tap again to wake it. Native eye expressions, smooth blinking, gaze, sleeping breath and floating “z” and short messages explain each response. |
| **Audio controls** | Master output volume, default output/input selection, supported microphone gain/mute, and an opt-in per-app mixer on the selected output. Stereo/mono Float32 routes use Core Audio process taps; the user accepted the Sprint 3 Mac checklist October 8. |
| **Menu-bar subpages** | Companion, Timers, AI, Audio, Clipboard and Avatars replace the long stacked panel. Avatar changes save immediately. |
| **Three timer modes** | The app and notch share a standalone countdown, Pomodoro with breaks/rounds, and stopwatch. Each supports pause, resume and reset; choosing a mode never starts a session. |
| **Dynamic island** | Matches the physical notch’s height and grows sideways. The companion strolls along the island and nudges the countdown during the final 30 seconds. Hover for a visual highlight; the first click opens controls even with another app active. The full activation strip, including the camera gap, toggles controls. Pointer exit allows 800 ms to cross between controls; keyboard reveal allows four seconds to reach them. |
| **Completion celebration** | The avatar comes down to announce completion and the break, then tucks away again. |
| **Persistent sessions** | Restores running deadlines, paused timers, completed sessions, and focus preferences after relaunch. |
| **Configurable activation** | Record separate companion and voice shortcuts, including modifier-only combinations, plus optional hover and impacts. |
| **Voice on demand** | Focus, installed-app launch and browser search commands execute automatically in English or Portuguese (for example, “open Safari”, “abra o WhatsApp” or “pesquise receitas”). A nod, checkmark, and message acknowledge an understood command. |
| **AI work nearby** | With one local-monitoring consent, follow Codex/Claude Code activity automatically, see limits and charts, and keep the active provider beside your avatar. |
| **Size and motion** | Choose Small, Medium or Large expanded widgets, compact timer density and character motion; macOS Reduce Motion is always respected. |

### Meet the companion

![The six Sieghart companions and their reactions](Sieghart/Design/Concepts/avatar-reactions-preview.png)

*Production native shapes based on the user-approved Simple Companions board, with matte light, soft shadow and a curved coral paper fold. Each canvas draws at its final display size for sharp edges in both the app and island. Eyes and expressions interpolate directly; no bitmap pose swapping.*

![Simple companions in motion](Sieghart/Design/Concepts/simple-companions-motion.gif)

*Offscreen 20 fps preview of native gaze, blinking and breathing. The app’s motion updates at 60 Hz and respects Reduce Motion.*

First launch opens an animated welcome, then presents all six companions in a three-column onboarding gallery, with each name and personality. Select your initial companion and continue. Later, open **Appearance** or the menu-bar **Avatars** tab to change it. The choice saves immediately and appears throughout the main app, widget, compact island, voice, completion celebrations, menu header, and menu-bar icon. All artwork is drawn locally and works offline. Legacy sprite assets remain archived in the repository and are excluded from the app bundle. CRT Buddy remains the default.

### A companion with context

![Companion with comfortable margins and no duplicated action row](Sieghart/Design/Concepts/island-companion-preview.png)

*Static renders of the production views, without opening app windows. The widget keeps only companion context inside the Buddy page. Side controls and the tool grid handle navigation; the menu bar uses six compact subpages with natural content heights.*

The compact island and camera strip stay sRGB black (`#000000`). Expanded pages offer optional Glass, an attached shoulder contour and circular quick controls around the surface. Appearance selects System, Light or Dark; separate switches control Glass in other windows/panels and in the expanded island. Both switches default off. macOS 26 uses Liquid Glass; older supported systems use behind-window blur. Reduce Transparency keeps an opaque surface. Native transitions reserve their full bounds so the moving silhouette does not resize or crop its content.

![Horizontal Pomodoro setup](Sieghart/Design/Concepts/island-pomodoro-preview.png)

*Offscreen production-view render; glass translucency is illustrated against a sample background. Native desktop refraction and movement still require a Mac run.*

### Main app

![Sieghart main window](Sieghart/Design/Concepts/app-overview-preview.png)

*Offscreen render of the production main window with illustrative AI data. Overview, Timers, Activation, Appearance, AI agents, Audio and onboarding share configurable solid/glass surfaces, palette and companions. The user accepted the associated Mac appearance checklist October 8; this image itself is an offscreen render.*

[Appearance](Sieghart/Design/Concepts/app-appearance-preview.png) · [Timers](Sieghart/Design/Concepts/app-timers-preview.png) · [Activation](Sieghart/Design/Concepts/app-activation-preview.png) · [AI dashboard](Sieghart/Design/Concepts/app-ai-preview.png) · [Audio](Sieghart/Design/Concepts/app-audio-preview.png)

[Sleeping motion](Sieghart/Design/Concepts/simple-companions-sleep.gif) · [Companion depth](Sieghart/Design/Concepts/simple-companions-depth-preview.png) · [Compact hover without an outline](Sieghart/Design/Concepts/compact-hover-preview.png)

[Explore the design prototype](Sieghart/Design/Prototype) · [Read the implementation notes](Sieghart/README.md)

### Audio and compact navigation

![Audio mixer with illustrative apps and levels](Sieghart/Design/Concepts/island-audio-preview.png)

Output selection, master volume and input-device controls use Core Audio hardware properties. Devices without writable volume/mute show unavailable controls. The per-app mixer is off after launch. **Enable app mixer** opts in; the button immediately starts the public macOS system-audio permission path before enabling app sliders. A failure provides Retry and Audio permission settings. The mixer processes audio locally without saving it or recording the microphone. It shows up to five actual running apps plus Master, prioritizes apps currently playing audio, groups helpers into their visible installed app, waits for an audio connection before enabling its slider, loads native app icons, identifies the selected device (including AirPods), adjusts each with a private process tap and aggregate playback route, and restores normal playback when disabled. Stereo process mixdown supports mono Bluetooth calls and planar/interleaved Float32 outputs; encoded/incompatible formats are rejected explicitly. Device format changes rebuild routes even with the same ID; restarted helpers can retry. The user reported all Sprint 3 manual checks passed October 8, including the audio/device checklist.

![Choose a companion from the menu bar](Sieghart/Design/Concepts/menu-avatars-preview.png)

The menu-bar panel is 380 points wide. Each tab replaces its content and fits its height, eliminating the empty 300-point content area. The island's ten-tile grid opens Companion, Audio, AI agents, Timers, Clipboard, Avatars, System, Keep awake, Display & power and Preferences; voice uses Companion. AI cards follow limits/spending → current work → hourly trend → models/projects → activity; hover/select a bar for exact tokens and estimated value. Connection details open separately, keeping island height bounded.

## Swift Student Challenge

The [currently published Apple requirements](https://developer.apple.com/swift-student-challenge/eligibility/), checked on October 5, 2026, call for an individual app playground (`.swiftpm`) submitted as a ZIP of up to 25 MB. The experience must work offline, include its resources locally, use English, and be experienced within three minutes. The playground must build and run with Swift Playground 4.6 or Xcode 26 or later. Requirements must be checked again for the target edition.

The main development project remains the macOS `.xcodeproj`. A submission adaptation is a separate milestone. Real accelerometer interaction remains a goal for the Challenge experience; its compatibility with an accepted playground destination still needs validation.

The judging experience should tell one clear story: meet the companion, reveal it through physical interaction, configure a focus session, and see its response. Keyboard controls and reduced motion keep the experience accessible. The core journey must work without network services, an account, or speech recognition. Voice and future integrations need a separate offline compatibility review.

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

1. Complete Welcome → choose one of six avatars → optional local AI/Clipboard tools. Optional voice/paste access setup is available there. Finish opens the companion with a special arrival; focus remains explicit.
2. Click the compact island or press **Control + Option + S** to reveal the companion. Hover gives a subtle companion reaction without outlining or opening the island.
3. Open **Timers** in the app or widget. Choose Timer for a countdown, Pomodoro for focus/break rounds, or Stopwatch for elapsed time.
4. Press **Start** for the selected mode. The widget tucks into the island; click it for pause/resume/reset controls. Pomodoro also offers Finish.
5. Open **Activation** or **Appearance** in the main window to customize the experience.

The menu bar also provides access to the widget and app. In Activation, press a shortcut recorder and enter any key combination; release modifier-only keys to save. Companion and voice bindings can be disabled separately. Impact gestures are off by default.

Closing the main window with its red button keeps Sieghart in the menu bar. An app delegate retains activation independently of the window and explicitly keeps the process running after the last window closes. Window closure cancels an unfinished shortcut recorder and recovers activation; **Quit** stops the app. A listen-only session event tap handles modifier gestures across apps and restarts after interruption; regular-key hotkeys register on the system dispatcher after AppKit finishes launching. Both overlay panels elevate their level when the foreground window covers the display, and disappear on session lock/sleep. The earlier intermittent shortcut interruption is resolved in [SG-001](Sieghart/BUGS.md) following user acceptance October 8. Healthy global registrations stay active across app/Space changes; permission changes or failed delivery setup trigger recovery. With an existing keyboard grant, both global delivery paths work with duplicate suppression. The user accepted the red-window-close and cross-app/full-screen shortcut checklist October 8.

## Voice and local data

Voice starts with its configured shortcut or **Speak** in Companion/menu. Listening, transcription, feedback and Cancel/Back use the Companion page itself; there is no separate Voice page or launcher tile. The default voice shortcut is **Control + Option + V**. Saved custom modifier-only bindings remain available; Activation offers the regular-key default without overwriting them. Modifier-only shortcuts use a listen-only session event tap with Input Monitoring access, or the AppKit global monitor with existing Accessibility access. Activation provides an explicit permission button; one of those grants is sufficient. Shortcuts containing a regular key use the system hotkey API. See [Apple’s event-monitor documentation](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)).

Speak a supported command and finish naturally. Recognition completion or a short pause executes it automatically; capture stops after at most ten seconds. Choose English or Portuguese in Activation. Try “start focus for 25 minutes”, “pause timer”, “resume”, “finish”, “show”, or “hide”. Unsupported, negated, or conflicting commands leave the timer unchanged. This is a local focus-command interface; open-ended AI conversation remains planned.

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

Run all deterministic checks:

```sh
bash Sieghart/Tests/run-checks.sh
```

These checks do not open the app, activate the sensor, register system shortcuts, request permissions, or record audio. They cover all three timer modes, countdown/stopwatch pause and restoration, explicit mode selection, interval counting, native first-click acceptance, activation-strip toggle, background speech authorization, voice execution and acknowledgement, shortcut persistence, modifier gestures, all six native menu icons, continuous eye/shape motion and Reduce Motion, repeated-touch reactions, wake-up behavior, exact compact notch height, island collapse, completion announcements during automatic breaks, real quota protocol fixtures, cloned-session deduplication, token arithmetic and spending persistence, AI lifecycle completion, long-turn metadata recovery, graph deduplication, first-run avatar persistence, click-only expansion, collapse of every panel, old-completion suppression, widget sizes, automatic price/tier/cache arithmetic, unpriced lower bounds and usage-based provider logos. The audio group exercises opt-in, failure states, same-ID device format changes, teardown and bounded Float32 mixing without hardware. A ninth group verifies Claude history formats/staleness, atomic CSV/JSON charge imports, export deduplication and broader archived history.

## Sprint 3 closeout

Sprint 3 is complete and accepted October 8, 2026: the user reported all manual checks passed. Implementation, nine isolated test groups and the signed universal build were completed October 7. Browser search, reviewed charge CSV/JSON import/export, expanded local/archived history and automatic Claude desktop quota reading complete the adapters. Real read-only Codex quota/counter sources were checked successfully; the last check found no fresh Claude reading on this Mac. SG-001 through SG-005 are resolved on the user’s report. Sprint 4 requested implementation is delivered; its new physical Mac checklist is linked at the top.

[Delivered scope and exact Mac checklist](Sieghart/Design/sprint-3-closeout.md) · [Charge import format](Sieghart/Design/charge-imports.md) · [Sources preview](Sieghart/Design/Concepts/ai-data-sources-preview.png) · [Search in Companion](Sieghart/Design/Concepts/island-companion-search-preview.png)

## Project map

| Location | Responsibility |
| --- | --- |
| [App](Sieghart/Sieghart/App) | Composition and resident application lifetime. |
| [Features](Sieghart/Sieghart/Features) | Views and ViewModels grouped by screen/feature. |
| [Core Services](Sieghart/Sieghart/Core/Services) | Voice, Core Audio, AI readers, pasteboard, monitor, power, display, input, calendar and native panels. |
| [Core Helpers](Sieghart/Sieghart/Core/Helpers) | Voice/search parsing, encoded URLs, shortcut rules, timer and notch value types. |
| [Shared](Sieghart/Sieghart/Shared) | Reusable avatars/controls, appearance options, preferences, activation/gesture services and assets. |
| [Tests](Sieghart/Tests) / [Design](Sieghart/Design) | Isolated checks, offscreen fixture previews and design/reference records. |

[Detailed MVVM organization](Sieghart/ARCHITECTURE.md). Native island presentation still has a coordinator; the hierarchy does not claim a complete protocol extraction of every AppKit window operation.

## AI usage

Onboarding asks once whether to follow local AI usage. When enabled, Sieghart detects installed Codex/Claude Code and refreshes in the background using existing provider sign-in. Open **AI limits** from the sidebar, Overview, menu or widget tools; say “What is my AI limits” to open the same panel. No extra API key is required for this local adapter.

The dashboard follows the reference screenshots: quota and spending cards, current project/model/output/elapsed work beside your avatar, a 24-hour chart, model/project rankings, and a 13-week activity heatmap with streak, active days and busiest day. Reliable active work also appears automatically in the compact island. Completion clears the work indicator; a focus timer remains available.

Codex supplies real 5-hour and weekly remaining percentages, resets and dated account activity. Hourly/model/project charts use deduplicated local logs and are marked **partial local history**. Missing readings remain unavailable. Disconnect stops provider reads and automatic reconnection.

Token value is automatic: bundled model prices work immediately, then the app refreshes public [OpenAI](https://developers.openai.com/api/docs/pricing) and [Claude](https://platform.claude.com/docs/en/about-claude/pricing) tables daily and keeps the last successful reading offline. It prices each known model's input, output and cache; documented OpenAI tiers and per-request long context are considered when recorded. Internal/unidentified models keep their tokens and show an unpriced amount; a partial value uses ≥. The value is an API-equivalent estimate, not a subscription charge. [Frankfurter](https://frankfurter.dev) supplies an automatic dated USD/BRL reference rate. These public requests send no account or usage data. Custom average prices/rates remain optional overrides; actual charges remain separate. Reviewed CSV/JSON charge import and JSON export are implemented; direct billing-account connection is not enabled.

Provider logos appear only when readings or usage show that provider was used. Model and project rows expose full integer totals. Hover or select an hourly bar for its range, input/output/cache tokens and value; select a heatmap day for its date and exact usage. Historical model context is recovered before the bounded log tail, including completed tasks. Absent metadata stays explicitly unattributed. Claude quotas read the desktop app’s fresh local plan history automatically; older/missing history is unavailable, reset dates are not inferred, and dated imported reports remain a fallback. Provider emblems are bundled vector assets, including the corrected OpenAI emblem for Codex; see [third-party notices](Sieghart/THIRD_PARTY_NOTICES.md).

![Complete AI dashboard rendered from production views](Sieghart/Design/Concepts/ai-dashboard-preview.png)

*Offscreen production-view render with labeled example data; no live app window was opened. [Six-avatar onboarding preview](Sieghart/Design/Concepts/onboarding-preview.png).*

## Roadmap and references

[Full roadmap](ROADMAP.md) · [39 reference screenshots](Sieghart/Design/References/Widget/README.md). The roadmap covers all 77 modules in the current reference catalog, foundational onboarding/settings, and companion interactions. Planned modules are not claims of shipped functionality.

### Timer previews

[Countdown](Sieghart/Design/Concepts/timer-timer-preview.png) · [Pomodoro](Sieghart/Design/Concepts/timer-pomodoro-preview.png) · [Stopwatch](Sieghart/Design/Concepts/timer-stopwatch-preview.png). Rendered from production SwiftUI views offscreen; the user accepted the associated Mac interaction/appearance checklist October 8.

### Simpler companion direction

[The approved Simple Companions board](Sieghart/Design/Concepts/avatar-simple-studies.png) is now implemented as native shapes across onboarding, Appearance, island and menu. All six preserve their saved identities. Expressions, gaze and blinking interpolate continuously; breathing, listening and acknowledgement use gentle shape movement. Legacy detailed artwork is archived and excluded from app resources. See [the design brief](Sieghart/Design/Concepts/avatar-simple-studies.md).

## Useful companion options

The proposed first additions are task handoff (open a completed AI/download result) and contextual quick actions (resume a clock, select AirPods, mute an app or keep awake). Other options are a local “where I stopped” note, verified meeting audio context and opt-in gentle reminders. The user also proposes a primary companion coordinating other avatar agents, and workflows that receive a file, upload it and prepare/send email with explicit authorization. Clear, resumable steps and fewer app switches support the user's ADHD-oriented product intention. Optional selected-repository PR/build alerts follow the core utilities. These are proposals, not shipped functionality. [Concrete experiences, dependencies and boundaries](Sieghart/Design/companion-capabilities.md).

## New companion reference

The user supplied Coucou as inspiration after accepting Sprint 3. [Reference study](Sieghart/Design/coucou-reference.md) records task/result hierarchy, coordinated motion, file handoff and small task-agent indicators. These are future design proposals; the six Simple Companions and confirmed interaction rules remain the product identity.

## Next steps

Sprint 3 is closed and the requested Sprint 4 implementation is delivered. New utility/greeting hardware acceptance is the current release gate. S5 then introduces calendar/reminders, notifications, downloads, a file shelf and capture; connected companion workflows follow the core utilities.

- Implement and validate the S4 utility scope when that sprint begins.
- Validate real sensor interaction in the accepted Challenge submission environment.
- Refine a three-minute, offline story with expressive interactions and accessible controls.
- Give future document interactions their own receive-and-carry animation when that feature is introduced.
- Prepare and verify the submission adaptation against the target edition’s rules.
- Continue Calendar, reminders, and conversational AI as later macOS milestones; Calendar is currently hidden.

## License

Sieghart is released under the [MIT License](LICENSE).
