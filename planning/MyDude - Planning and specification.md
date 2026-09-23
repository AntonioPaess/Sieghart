---
title: MyDude - Planning and specification
date: 2026-09-13
status: proposal-for-discussion
tags: [mydude, planning, macos, swiftui, swift-student-challenge, adhd]
---

# MyDude — planning and specification

Related: [[MyDude - Project context]]

This document records the product request, project context, technical decisions, open questions, implementation roadmap, validation criteria, and execution history. It is a planning document; a proposal is not proof that a capability is technically available. Apple sources were reviewed on 2026-09-13. Effort ranges are estimates, not delivery dates.

## 1. Vision and open decisions

Sieghart is a discreet Mac partner that gathers and organizes useful information from authorized sources, understands the day's context, and performs requested actions. It brings together calendar events, tasks, reminders, Pomodoro sessions, and service information such as Codex and Claude limits. It helps a person understand what needs attention and act without opening several apps. Its visual presence and supportive tone are part of the product. The proposal should be evaluated with people who have ADHD; it does not assume that everyone has the same needs and does not promise treatment.

**Confirmed request:** native Swift and SwiftUI; a character near the notch; voice and text; persistent calendar and reminders; a daily view; Pomodoro; available Codex and Claude limits; a meeting warning five minutes before it starts and an action to open its link; preference for Apple Intelligence; AirPods; and keys for other AI providers. The physical sensor is a requirement for the Challenge version, not an optional later extension. Health features come later. Initial documentation was completed and implementation of the Sieghart project began on 2026-09-20.

**Confirmed priority:** Challenge first, followed by evolution into a full macOS product.

**Confirmed development format:** MyDude is built as a native Xcode macOS project (`.xcodeproj`), not as a Swift Package Manager app playground. The architecture, sensor, notch panel, and integrations are planned around this main project.

**Technical name defined on 2026-09-20:** `Sieghart`. `MyDude` remains the concept and documentation name until product identity is finalized. “Sieghart” is distinctive and may work as the character or product name; before publication, review pronunciation, cultural associations, and trademark availability.

**Interaction clarification:** the inspiration is SlapMac, which reacts to physical impacts on a Mac. MyDude uses that type of trigger for useful actions. Do not confuse this idea with ordinary taps on glass or assume that the hardware can prove which side received an impact. The sensor is the accelerometer or IMU; a Challenge-compatible access path still needs validation.

**Reference identified on 2026-09-13:** the app is [SlapMac](https://slapmac.com/). The confirmed concept is to read the internal accelerometer or IMU on compatible MacBooks, classify an impact, and convert it into an action. The [MacMagazine article](https://macmagazine.com.br/post/2026/03/30/slapmac-e-um-app-que-reage-com-som-a-tapas-acidentais-ou-nao-no-mac/) confirms accelerometer use, adjustable sensitivity, and menu bar operation. The official site states macOS 14.6+ and MacBook M1 Pro or later. Do not copy SlapMac branding, identity, sounds, or appearance; it is a technical and interaction reference.

**Second reference identified:** the [Instagram post](https://www.instagram.com/p/DZ-2a9JIFXK/) describes an app that uses head-position data from AirPods to provide posture reminders during Pomodoro focus sessions. For MyDude, this inspires an **opt-in focus and head-position mode**, not permanent monitoring. The post does not identify the app, repository, accuracy, compatibility, or validation method; those points remain open.

**Current direction:** a personal information aggregator that can act and remember, also triggered by the sensor. The earlier suggestion to center the product on “I am stuck” remains a possible feature, not the product definition. Keep a short Challenge experience and a fuller everyday macOS experience while sharing the core logic.

**First implementation:** `Sieghart.xcodeproj` contains an experimental `AppleSPUHIDDevice` reader, an impact detector, diagnostic controls in the main window and menu bar, a local Pomodoro action, a configurable impact-action coordinator, a face-only native notch panel, and a read-only calendar context card. The macOS build passes in Xcode 27. The current environment is a Mac15,7 with an Apple M3 Pro; `ioreg` confirmed a usage-3 device with 22-byte reports. A hardware run confirms that reports arrive and impacts can be routed into local actions.

### Desired concrete interactions

| Request or situation | Expected result |
|---|---|
| “How much Codex and Claude capacity do I have?” | Availability by service and window, renewal time when provided, source, and last update |
| Meeting starts in five minutes | Warning with title and time, plus an action to open the correct link |
| “Open my meeting” | Find the relevant meeting, resolve ambiguity, and open an existing link |
| “Start a Pomodoro” | Start focus with a configurable default duration, pause, and persisted state |
| “Put this on my calendar” | Resolve date, duration, and calendar, then save with an appropriate review step |
| “Remind me to submit the assignment” | Create a reminder with a due date and chosen repeat policy |
| Reminder remains pending | Remind according to the agreement; allow snooze, completion, or silence |
| “What do I have today?” | Summarize events, overdue tasks, and today's pending items without inventing priorities |

“Accumulate” means keeping useful, consented, up-to-date context. It does not mean storing everything the person does on the computer indefinitely.

**Questions for future conversation:**

- Which Challenge edition is the target? Competition-first priority is already confirmed.
- What should appear first when the Dude is called: the next meeting, pending items, or a daily summary?
- Which macOS versions are installed on the three Macs, and what is the exact model and year of the Intel i9?
- Which AirPods are available for testing the optional head-position mode?
- Should the character sound like an informal friend or a calm, direct presence? When may it take initiative?

## 2. Feasibility and scope boundaries

| Capability | Technical situation | Proposed decision |
|---|---|---|
| Calendar and reminders | EventKit with separate authorizations | High priority; fictional data in the Challenge demonstration |
| Voice and text | Speech and AVFoundation; local recognition depends on availability | Text always available; voice only after explicit activation |
| Apple Intelligence | Foundation Models with a local model on eligible devices | Check availability at runtime; keep a deterministic fallback |
| Notch | AppKit panel beside the camera region | No drawable pixels exist over the physical cutout |
| Touches inside the app | AppKit delivers touch events associated with views | Later experiment; do not depend on global capture |
| Physical impacts near the trackpad | Accelerometer or IMU concept confirmed; technical access in `.xcodeproj` still under validation | Central requirement; first investigation and critical dependency |
| Apple Health on Mac | Framework availability does not provide a usable Mac HealthKit store | Future iPhone companion with explicit transfer |
| Sitting time and posture | Computer use does not prove body posture | Manual check-ins and clearly labeled estimates |
| AirPods | Audio follows system devices; motion depends on hardware and API support | Audio first; motion as a separate experiment |
| External APIs | Network and credentials required | Optional product feature, outside the required Challenge path |
| Codex and Claude limits | Subscription source still needs provider-specific validation | Independent connectors; clearly labeled demonstration data in the Challenge |

Trackpad touch APIs are associated with views, not a generic shell sensor. Core Motion must not be treated as a trackpad API. [NSTouch](https://developer.apple.com/documentation/appkit/nstouch) · [Touch events](https://developer.apple.com/documentation/appkit/nsresponder/touchesbegan(with:))

### Initial hardware matrix

| Available machine | Proposed role | Current expectation |
|---|---|---|
| User's MacBook Pro with M3 Pro | Development and primary sensor reference | Within the M1 Pro+ requirement stated by SlapMac; validate reads in the Challenge project |
| User's Intel i9 Mac | Compatibility and fallback | Not listed as compatible by official SlapMac; identify model, year, and sensor before drawing conclusions |
| Friend's MacBook Air M5 | Generalization across Apple silicon families | Requires real testing; official SlapMac wording says M1 Pro+, while similar projects make broader claims |

For each machine, record model identifier, macOS version, HID or sensor service presence, observed sampling rate, required permission, threshold, false positives, power use, and `.xcodeproj` behavior. The Pro, Air, and Intel differences are useful research, but the demonstration must state its required hardware clearly.

HealthKit on macOS does not provide the same read/write health store available on iPhone; availability checks are required for multiplatform targets. [HealthKit architecture](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework)

## 3. Swift Student Challenge relationship

The main project is a macOS `.xcodeproj`. Based on the rules reviewed on 2026-09-13, the current Challenge submission asks for a `.swiftpm` app playground in a ZIP up to 25 MB, a self-contained experience of up to three minutes, offline operation, local resources, English content, and individual authorship. The rules cite Swift Playground 4.6 or Xcode 26 or later. Therefore, the `.xcodeproj` should not be considered directly submit-ready under those rules. The target edition still needs to be selected; do not assume that the 2026 rules or calendar apply to a later edition. [Official requirements](https://developer.apple.com/swift-student-challenge/eligibility/)

Development starts and remains in the macOS project. **Required future milestone:** validate accelerometer reads in the `.xcodeproj` on the M3 Pro and in the intended sandbox and distribution configuration. Once the target rules are published, choose among: a separate `.swiftpm` adaptation that reuses compatible logic; the new format if the rules change; or keeping MyDude as an independent macOS project without forcing a conversion that removes its differentiator. This decision must follow the actual rules and a technical proof. The physical sensor remains a required part of the intended competitive experience.

### Proposed 180-second story

1. 0–30 s: introduce the assistant and explain the physical trigger; a real sensor impact makes the Dude appear.
2. 30–65 s: show a fictional daily summary with an event and reminder; identify the data as demonstrative.
3. 65–100 s: show an upcoming meeting warning and access card; demonstrate a local open action without requiring network access during judging.
4. 100–145 s: a configured gesture starts a Pomodoro; immediate visual feedback proves the sensor-to-action path.
5. 145–180 s: a pending reminder appears, the person snoozes or completes it, and the assistant confirms the result. Any time advance is labeled as a demonstration.

If a Challenge-specific version is required, it should not require an account, API key, personal calendar, AirPods, iPhone, or downloaded model. Sensor permissions and hardware must be compatible with judging. Buttons and keyboard remain accessibility alternatives, but they do not replace the physical sensor requirement. The offline conversation mode uses limited local intents and responses as a guided experience; it does not pretend to be open-ended generative conversation. Online integrations use explicitly labeled local samples rather than pretending to perform a live query.

Before submission, re-check eligibility, edition, deadline, format, language, size limit, accepted tools, credits, and AI-tool rules. Prepare a personal explanation of the problem, accessibility choices, technologies, and asset attributions. Test the extracted ZIP offline in a clean environment. No submission is planned at this stage.

## 4. Proposed architecture

Start with a small project organized by responsibility; do not create many packages or a backend for the MVP. Shared domain code must not import AppKit, EventKit, or HealthKit.

| Logical component | Responsibility |
|---|---|
| SwiftUI interface | Conversation, next step, focus, settings, and accessibility |
| Interaction coordinator | Current state, cancellation, and one interaction at a time |
| Domain core | Intents, action proposals, focus sessions, and interruption policy |
| Conversation service | Local Apple implementation, guided offline implementation, and optional external implementation |
| Voice service | Capture, transcription, and synthesis independent of the language model |
| Calendar repository | EventKit implementation and fictional implementation |
| Context aggregator | Authorized source snapshots with origin, update time, and availability |
| Service connectors | Codex and Claude limit queries through mechanisms whose feasibility is still being checked |
| Notification planner | Next meeting, repeated reminders, snooze, and deduplication |
| Action executor | Open validated links, start Pomodoro, create events or reminders, and confirm results |
| Local repository | Preferences, sessions, and consented check-ins |
| macOS host | Notch panel, menu bar, windows, and focus behavior |
| Gesture input | Convert validated gestures into intents without executing actions directly |
| Future wellness bridge | Receive consented summaries from a companion and preserve their origin |

Flow: trigger → voice or text → intent → minimum permitted context → proposal → validation → confirmation for external changes → execution → real result → text, voice, and expression.

The model proposes; the domain validates; services execute. Generated text must never write directly to the calendar. Keep “proposed event” separate from “saved event.” Event content, transcripts, and external responses are data, never instructions to change permissions or send information.

Conceptual models: interaction preferences; transient message; intent; action proposal with title, start, duration, calendar, and state; focus session with start and end; check-in with value, unit, time, and origin. Reference EventKit identifiers instead of duplicating the entire calendar. Own IDs prevent duplicate execution after a retry.

Add a context snapshot with source, query time, expiration, and authorization state; a usage window with unit and renewal when provided; a meeting with its source link; and a reminder policy with interval, quiet hours, and next occurrence. Separate factual data, estimates, and generated suggestions. An unavailable connector must not block the other sources.

Proactive flow: a source changes or a time arrives → revalidate state → apply interruption preferences → deduplicate → present an action → record the response. Never depend on a language model to count time or decide whether a reminder is already complete.

Use Swift Concurrency for asynchronous work, keep visual state on the MainActor, and serialize shared resources. Cancel generation and capture when the person closes the interaction. Persisted actions need an explicit result; a visual cancellation must not hide an action that already ran.

## 5. Calendar and reminders

Use EventKit with a long-lived `EKEventStore`. Request access only when a feature is used: calendar reading requires full access, while creating events can use write-only access. Reminders have a separate request. Configure usage descriptions and calendar entitlements for the sandboxed macOS app. EventKitUI on iOS is not the native AppKit interface; on Mac, render the review step in SwiftUI. [Event store](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) · [Authorizations](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:))

For “reserve twenty minutes tomorrow,” resolve date, time zone, and duration; ask only for missing information; inspect conflicts only with permission; show a card with the full date and calendar; then save after confirmation. Keep recurring events out of the first version. Allow undo only for the event created by the Dude, after checking for later external changes.

Handle denied or revoked permission, read-only calendars, no writable calendar, external changes, time zones, and daylight-saving changes. Refresh on event-store changes and when returning to the interaction, without continuous polling. The fictional mode uses a separate repository and never writes to the real calendar.

### Meetings, routine, and repeated pending reminders

For meetings, schedule a configurable five-minute warning and reschedule it when an event changes or is canceled. Read URLs from available event fields and inspect notes or location when necessary. Show the destination and handle multiple links or simultaneous meetings; never invent a URL. Open only after a request or an explicit warning action. Automatic opening is a separate future preference, not an inference from calendar permission. Event text must never instruct the app to execute arbitrary commands.

For reminders, due date, completion state, and follow-up policy are separate entities. The initial proposal lets the person choose a repeat interval and active hours, with actions to snooze, complete, or stop reminding. Stop after completion in the Reminders app, a due-date change, or revoked permission. Decide whether a warning comes from the system, the Dude, or both to avoid duplicates. Plan local UserNotifications while validating permission and delivery limits on the chosen target; the app's own panel depends on the app running. On wake, re-evaluate pending items without dumping every missed warning at once.

Pomodoro states are ready, focus, pause, paused, and completed. The duration is configurable, a clear request starts immediately, and cancellation is available. Calculate time from timestamps and persist the session for resumption instead of relying on an in-memory counter. The daily summary combines calendar and overdue or planned tasks with source and time; it never turns an AI suggestion into an obligation.

### Codex and Claude limits

This is a product information requirement, separate from using these models for conversation. Authenticating to a generation API does not prove access to an app subscription quota. This document has not verified how each service exposes that data to an independent macOS app. A capability in the Codex environment also does not prove that an equivalent public API exists for MyDude.

Future provider investigation: identify an officially supported and authorized mechanism, account scope, returned windows and units, renewal, and allowed frequency. Do not assume endpoints, reuse cookies, or read credentials from other apps. If no viable integration exists, show “query unavailable” and link to the official usage page; never invent percentages. Record the technical verification date because integrations can change.

Each service gets its own card: remaining capacity when actually reported, window, renewal, and last update. Do not compare percentages from different windows as equivalent or confuse subscription capacity, API credits, and context length. Query on demand with explicit cache validity; background refresh is allowed only when supported and consented. For the Challenge, these cards may use identified offline examples or be omitted to make room for the sensor.

## 6. AI and voice

Proposed base: stable APIs available on macOS 26+, with availability checked at runtime. Use `SystemLanguageModel` and `LanguageModelSession` for short responses and structured proposals within the capabilities verified in the selected SDK. Do not depend on beta APIs or newer cloud features. Apple Intelligence enabled, eligible hardware, and a ready model are separate conditions. [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)

Limit context to the request, the preferred tone, and authorized relevant upcoming times. Keep conversations short, enforce size limits and timeouts, and handle refusal and error. The app owns dates, conflicts, and persistence. If the model is unavailable, use guided mode; do not silently send the request to an external provider.

Voice: activate the microphone through a button or shortcut, capture with `AVAudioEngine`, transcribe with Speech, and synthesize with `AVSpeechSynthesizer`. Check local recognition support for the chosen language and require on-device processing only when it is supported. Do not promise offline Portuguese recognition on every Mac. If local resources are missing, keep text available and explain the limitation. [On-device recognition](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)

Show editable transcription. Stop capture before the assistant speaks to avoid feedback and offer an interrupt control. Keep the microphone off while idle. Do not use a permanent wake word in the MVP. Configure microphone and speech usage descriptions and required entitlements; validate them in a sandboxed build.

AirPods follow the input and output devices selected in macOS, without a custom Bluetooth pairing flow. Handle disconnection during capture and audio-format changes. Pause before speaking through speakers after the headphones disconnect, so a private response is not exposed unexpectedly. Validate on real hardware; do not assume unchanged playback quality while the Bluetooth microphone is active.

Future external providers use URLSession adapters with optional streaming, cancellation, timeout, authentication errors, and usage limits. Store keys in Keychain, never in SwiftData, UserDefaults, versioned files, or logs. Show the provider and data being sent before first use. Do not forward health history by default. Do not automatically repeat a calendar action when retrying a generation request.

## 7. Notch and sensors

The macOS host uses a borderless `NSPanel` with `NSHostingView`; the panel is nonactivating for passive presence, with an explicit focus policy for typing. `MenuBarExtra` remains the permanent access path and fallback. Calculate geometry from `NSScreen` and safe areas while considering the selected display, resolution, scale, and monitor changes. Draw below or around the camera, never behind it. [Panel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel) · [Safe areas](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets)

Validate Spaces, full screen, Stage Manager, hidden menu bars, external monitors, and Macs without a notch. Do not steal focus while the person works. If an overlay is unreliable in a configuration, provide a menu bar popover. Do not promise an overlay over protected system screens.

Later trackpad experiment: an `NSView` integrated with SwiftUI can receive indirect touches through `allowedTouchTypes`. Track begin, move, end, and cancel by identity; reject drag and scroll; distinguish a tap sequence from simultaneous fingers. Separate clicks from non-click touches. [Touch types](https://developer.apple.com/documentation/appkit/nsview/allowedtouchtypes)

One tap could open, two could start voice, and three could collapse, **only as an experimental mapping**. Wait for the two- or three-tap recognition window before firing a single tap; calibrate time and movement thresholds in testing. Provide disabling and configuration. Do not map a gesture to external recording without a separate review. Delay and accidental triggers may make a button or shortcut preferable.

Global multitouch capture is not validated by the cited APIs. A global event monitor is not access to every trackpad contact. Do not use private frameworks or indiscriminate keyboard capture. Taps on the shell are a separate investigation; do not assume that Force Touch or the Mac accelerometer detects them through a public API.

**Required physical-impact investigation:** the sensor is an accelerometer or IMU. The next step is to validate a usable `.xcodeproj` path with permissions, hardware, sandbox, and distribution. A similar open reimplementation documents `AppleSPUHIDDevice`, IOKit HID reads, gravity filtering, and detector voting; it also uses private APIs for visual effects, which Sieghart does not need. This is evidence of a possible technique in a macOS app, not confirmation of a public API, App Store support, or Challenge compatibility. Some secondary sources call the access Core Motion; until an SDK and hardware proof exists, do not record Core Motion as the confirmed solution. Compatibility with a possible submission artifact is a separate investigation. [Technical reimplementation](https://github.com/AbdullahFID/MacSlapApp) · [IMU reader](https://github.com/olvvier/apple-silicon-accelerometer)

Compare detection against typing, resting a wrist, moving the Mac, moving the desk, and closing the lid. An accelerometer detects impact on the device as a whole and may not prove that it came from the right side; that location requires experimentation. The button is an accessibility alternative but does not satisfy the Challenge sensor requirement by itself. An impact may open the Dude or start Pomodoro, but it must not by itself confirm a calendar change, open sensitive links, or send data.

Required investigation output: accelerometer → samples → filter → detector → intent; compatible Mac list; APIs and entitlements; macOS project behavior; permissions; power use; latency; and false-positive rate. Then evaluate separately whether this core can join any submission version required by the rules. Do not call the differentiator complete based on animation or simulation. Interaction must work with light, comfortable taps without encouraging hard impacts. Calibrate sensitivity, time window, and cooldown per machine.

## 8. Health and wellness — after the core

First step: optional break reminders and manual water logging. Time since focus began means session time, not measured sitting time. Do not infer posture, hydration, or a diagnosis from missing interaction.

Future step: an iPhone companion accesses HealthKit with granular authorization. Apple Watch may enrich available data; Watch–iPhone and iPhone–Mac communication are separate links. WatchConnectivity is not a generic direct Watch–Mac bridge.

In the companion, check `isHealthDataAvailable`, request only useful types, and record origin and units. Water may use `dietaryWater` when written by an authorized source; opening the app does not automatically measure intake. Missing data does not mean zero and does not prove that read access was denied. Incremental queries must handle updates, deletions, and duplicates. [HealthKit setup](https://developer.apple.com/documentation/healthkit/setting-up-healthkit)

For the bridge, begin with voluntary export and import of a minimal summary; study authenticated local synchronization later. Define separate consent, expiration, deletion on each device, and transport encryption before automation. Do not assume Apple Health synchronization makes data available to Mac; do not adopt CloudKit to copy health data without reviewing applicable restrictions.

AirPods motion is an independent investigation using `CMHeadphoneMotionManager`, `isDeviceMotionAvailable`, and a motion usage description. It may provide head orientation on supported hardware; it does not measure spinal posture. Validate compatibility and calibrate before proposing feedback. [Headphone motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager)

**Optional mode inspired by the second reference:** the person starts a focus session and chooses “track head position.” During the session, compatible AirPods detect sustained deviation from an initial calibration and provide a discreet reminder. The mode ends with the session or by command. The interface must call it a head-position signal, not a diagnosis or full posture measurement. Show that the sensor is active, allow recalibration and muting, and fall back to a normal Pomodoro when AirPods disconnect.

## 9. Design and interaction

The supplied image suggests a rounded black body integrated into the top edge, vertical light eyes, simple eyebrows, and a smile. Use it as direction while creating an original character. Avoid constant high-intensity glow and permanent animation; the reference is not a distribution-ready asset.

Initial palette: charcoal `#151419`, cream `#FFF4DA`, lavender `#B8AAEF`, and mint `#9EDAC4`. Accents appear briefly. Measure final text contrast; state must never depend on color alone. Use system typography, readable text, and one primary action per card. Start with short SwiftUI vector animations around 150–300 ms and respect Reduce Motion.

| State | Behavior |
|---|---|
| Resting in notch | Minimal character; sensor may be armed; conversation microphone off, detection technique still under validation |
| Inactive or hidden | Menu bar access only; no animation or sensors |
| Active | Short context summary, next meeting or pending item, and text field |
| Listening | Explicit indicator, transcription, and stop button |
| Processing | Subtle expression, progress, and cancel |
| Waiting for confirmation | Exact action and confirm, edit, and cancel buttons |
| Speaking | Light expression, written response, and interrupt |
| Focusing | Readable time on demand without distraction |
| Paused or unavailable | Plain explanation and a functional alternative |

Voice, text, and gestures feed the same intents and policies. Escape closes or cancels where appropriate; keyboard and VoiceOver complete the entire flow. Facial signals have text equivalents. Provide silent mode, adjustable pause time, and an intervention limit.

Proposed tone: “What is the smallest next step?”; “Would you like to reserve ten minutes?”; “We can return to this when it makes sense.” Avoid guilt, punitive streak loss, infantilization, or repeated prompts after refusal. The personality should feel supportive without pretending to be human or a health professional. Proactivity starts disabled or is explicitly configured.

## 10. Data, privacy, and performance

Use SwiftData for structured local records, UserDefaults for simple preferences, and Keychain for secrets. Store data in the app container with synchronization off by default. SwiftData does not automatically provide database encryption: add protection only if a later scope justifies it and do not promise protection that is not implemented.

Audio and transcripts are transient by default; conversation history is saved only when requested. Proposed configurable retention is 30 days for sessions and check-ins, with delete-all and selected export. Technical logs must not contain speech, calendar titles, health data, or keys. Document what leaves the device for each provider. Removing a key must also stop future use of that provider.

Distinguish a visual resting state with the sensor armed from a fully disabled state: the former may need low-power monitoring, still to be measured; the latter captures no sensors or audio. Conversation microphone stays off outside an interaction. If physical detection depends on audio, revisit this policy explicitly before implementation. Avoid frame-by-frame idle animation. Timers use start and end dates to survive sleep and wake; update the UI only while visible. Reuse audio resources with an explicit lifecycle. Limit model context and release memory when possible. Measure with Instruments in Release on the reference Mac, separating armed-sensor and disabled states.

Initial targets, not measured results: open the panel within 200 ms; average idle CPU below 1% for five minutes on the documented machine; no continuous memory growth after twenty cycles; and no network traffic in offline mode. Measure transcription and generation latency separately before setting final budgets.

## 11. Prioritized roadmap

| Phase | Indicative effort | Future delivery and dependency | Exit criterion |
|---|---|---|---|
| 0 — Sensor in macOS project | 3–5 days of initial investigation; final duration open | Create `.xcodeproj`, prove IMU reads on M3 Pro, identify APIs and permissions, and measure Intel/Air | Real sensor is viable in the macOS app with documented limits |
| 1 — Architecture, context, and sensor | 4–6 days after viability | Sensor triggers character and Pomodoro; local aggregator with fictional calendar and reminders | Real physical trigger and local journey, with an accessible alternative |
| 2 — Voice and calendar | 5–7 days | Capture, TTS, and an EventKit adapter on the appropriate target | Proposal is reviewed and saved once; denied permission does not block the journey |
| 3 — Local AI | 3–5 days | Foundation Models adapter and structured validation | Guided journey remains functional when AI is unavailable |
| 4 — Meetings and follow-up | 3–5 days | Warnings, links, repeated or snoozed pending items, and daily summary | External changes do not create stale or duplicate warnings |
| 5 — macOS project polish | 5–7 days | Validated sensor, accessibility, assets, and story | Stable macOS experience demonstrable in three minutes |
| 5B — Submission adaptation | Estimate after target rules are published | Verify format and port only compatible pieces if needed | Artifact meets the actual edition rules without claiming missing capabilities |
| 6 — macOS evolution and connectors | Estimate after sources are validated | Real notch panel, Codex and Claude limits, authentication, and cache | Real integrations verified with source and update information |
| 7 — Wellness and Health | Separate cycle after study | Manual logging, then companion and consented bridge | Correct origin, missing data, revocation, and deletion behavior |
| 8 — External providers | Separate cycle | Keychain, URLSession, consent, and visible cost or usage | Provider failure does not harm local functions |

Current order: macOS project and sensor feasibility → sensor and local context core → voice and calendar → AI → warnings and polish → evaluate Challenge adaptation → service connectors → Health. Hardware investigation is a critical dependency because of the user's explicit decision. For a solo project, reserve 25–30% schedule margin; reduce connector count and feature breadth before removing the sensor. Do not promise a sensor schedule while the technique remains unknown.

## 12. Validation and success criteria

| Area | How to validate |
|---|---|
| Benefit | At least four of five participants can check the day and complete a useful action without navigating several apps; record a small sample and comments without claiming clinical efficacy |
| Calendar | Time-zone, conflict, denied permission, and double-click cases; no write before confirmation and no duplicate |
| Meetings | Five-minute warning in the tested app and environment; reschedule or cancel updates the warning; correct link and missing link are handled |
| Pending items | Snooze respects the interval; completion outside the Dude ends follow-up; silent mode does not accumulate a flood of warnings |
| Pomodoro | Start by request and sensor; pause, resume, app restart, sleep, and wake preserve coherent time |
| Service limits | Data matches an authorized source at the same instant; show window and update time; expired credentials or missing source never become zero |
| Voice | Target-language phrases on target hardware; editable transcription; denied permission; AirPods disconnect; text always works |
| AI | Twenty representative, ambiguous, and out-of-scope requests; no unvalidated execution; missing model and timeout covered |
| Notch | One notched monitor, one without a notch, full screen, Space changes, and sleep or wake; no accidental focus loss |
| Gestures | At least fifty attempts per gesture during normal work; initial target of 95% recognition and zero accidental trigger in the test session, without generalizing from a small sample |
| Health | Distinguish manual, estimated, and imported values; missing data is not zero; denial, revocation, deletion, and duplicate import do not corrupt history |
| Accessibility | Entire flow through keyboard and VoiceOver, without audio and with Reduce Motion |
| Privacy | Inspect logs, persistence, and network; no plaintext keys or audio in logs; offline mode makes no requests |
| Challenge | After target rules are published: accepted format, three-minute story, and real sensor working on the admitted hardware or destination; never assume `.xcodeproj` is directly submit-ready |

## 13. Next steps

- [x] Define the Dude as a personal context aggregator that informs, acts, and follows up on pending items.
- [x] Record service-limit queries, five-minute meeting warnings and links, Pomodoro, calendar, reminders, and daily view.
- [x] Make a real sensor a Challenge requirement and the first roadmap validation.
- [x] Prioritize the Challenge with later macOS evolution.
- [x] Define the macOS `.xcodeproj` as the main project; do not develop MyDude as `.swiftpm`.
- [ ] Identify the target Challenge edition.
- [ ] Once the target rules are published, decide whether a separate submission adaptation is needed.
- [x] Record the inspiration of physical taps near the trackpad for useful actions.
- [x] Identify SlapMac, confirm the accelerometer concept, and record the three available Macs.
- [x] Record the AirPods, head-position, and Pomodoro reference as an opt-in mode.
- [ ] Record macOS versions, the Intel i9 model and year, and the AirPods model.
- [ ] Approve the three-minute story and proactivity limits.
- [ ] Sketch five screens or states and example lines while keeping this document a proposal.
- [x] Start the macOS project and initial accelerometer proof.
- [x] Run **Start sensor** on the M3 Pro and record result, permission, rate, and false positives.
- [ ] Test configurable one-, two-, and three-impact mappings on the M3 Pro and calibrate the recognition window and cooldown.
- [ ] Test calendar permission and event-link behavior with a real calendar and record the exact status for granted, denied, and empty-calendar cases.
- [ ] Test the three-impact calendar widget flow, including first permission request, upcoming-event animation, and hiding the panel with a new impact.
- [x] Establish English as the language for all project documentation, source comments, README content, and user-facing prototype strings.

Out of MVP scope: clinical posture inference, automatic health synchronization, a backend, and paid API dependence. Complete online integrations belong to macOS evolution; identified offline samples may demonstrate the vision in the competition. Permanent listening is not approved. The physical sensor remains required for the Challenge, and its technical path still needs validation. This document records requirements and proposals, not proof of implementation.

## 14. Execution log

This log accompanies implementation. Every phase must document what was done, why it was done, relevant decisions, validation, limitations, and the corresponding commit. Update the vault record with the phase delivery before starting the next phase.

### Phase 0 — macOS project and initial sensor proof — 2026-09-20

**What was done:** created the native `Sieghart.xcodeproj` SwiftUI project with a main window, menu bar entry, start and stop controls, and an experimental `AppleSPUHIDDevice` reader. Added an impact detector with a magnitude baseline, initial sensitivity, and cooldown to reduce repeated triggers. Published the project to `AntonioPaess/Sieghart` on `main`.

**Why:** the physical sensor is an explicit requirement for the Swift Student Challenge experience and a central product differentiator. Before voice, calendar, or AI integrations, we need to know whether the reference hardware can provide usable reads and whether an impact can become a useful action.

**Decisions:** keep `.xcodeproj` as the main project; isolate the HID reader behind a protocol so its source can change without rewriting the interface; start with visible diagnostics instead of immediately binding the impact to an action; do not add private APIs for visual effects.

**Validation at the end of Phase 0:** Debug build completed for Apple Silicon and `x86_64`; on the development Mac (Mac15,7, Apple M3 Pro), `ioreg` confirmed an `AppleSPUHIDDevice` usage-3 service with a 22-byte report. The runtime check was intentionally carried into Phase 1, where the binary was run and real reports and impacts were confirmed.

**Limitations:** the `AppleSPUHIDDevice`/IOKit HID path is experimental and does not confirm compatibility with a Challenge submission artifact, the Intel i9, or the M5 Air. Record compatibility per machine; an `x86_64` build does not prove that the Intel Mac has the required sensor.

**Commit:** `f846bad` — `feat(sensor): start native macOS project`.

### Documentation language decision — 2026-09-20

The user requested that project documentation, README files, source comments, and user-facing prototype strings remain in English. The conversation itself may be in Portuguese. Code comments and technical documentation therefore remain English, while the working conversation follows the user's preferred language.

### Phase 1 — Sensor-to-Pomodoro path and zero-report diagnostics — 2026-09-20 (completed)

**What was done:** added a small local assistant state model with a 25-minute Pomodoro, pause/resume/reset actions, and an impact counter. Connected the sensor's impact callback to that model. Added a visible report counter and changed the status text so the interface distinguishes an opened sensor from a sensor that has actually delivered reports. Translated the remaining prototype labels and comments into English.

**Why:** the first hardware run showed the original status could say that the sensor was active even when no acceleration sample appeared. That wording hid the most important diagnostic fact. The next run must prove the full path in order: HID device selected, report received, acceleration decoded, impact classified, and action executed.

**Sensor fix:** the reader now filters for the SPU transport, primary usage 3, and a report size compatible with the observed 22-byte accelerometer report. It derives the input buffer size from the device property, schedules the manager and device on the main run loop before opening, and sends an experimental `ReportInterval` request to `AppleSPUHIDDriver`. The wake request is best-effort because this is an undocumented hardware path and some systems may already be streaming.

**Validation:** the updated arm64 and x86_64 Debug builds succeed with code signing disabled. On the M3 Pro hardware run, the app displayed acceleration values, reached 4,992 received reports, detected 17 impacts, and changed the Pomodoro state in response to impacts. The test ended with the sensor stopped and the Pomodoro paused at 24:37 remaining. This confirms the complete path from HID report to decoded acceleration, impact detection, and a useful action.

**Limitations:** this result confirms the M3 Pro path only. The `AppleSPUHIDDevice` and `AppleSPUHIDDriver` path remains experimental and may differ across the Intel i9 and M5 Air. The impact detector still needs calibration against deliberate taps, accidental movement, sleep/wake, and a longer idle session before it is connected to more consequential actions.

**Commit:** `afa5d91` — `feat(sensor): connect impacts to pomodoro`.

### Phase 2 — Notch widget, configurable impacts, and calendar context — 2026-09-20 (in progress)

**What was done:** added an AppKit `NSPanel` controlled by `NotchWidgetController`, positioned flush with the top edge and centered using the display's auxiliary top areas when macOS exposes notch geometry. The panel is hidden by default. A small AppKit tracking panel covers only the notch zone and reveals the character while the pointer is there; leaving the character schedules a short hide. An impact can reveal or hide it, depending on the configured action. The panel's SwiftUI content keeps the original face as its primary surface: blinking eyes, breathing scale, and a focus expression. It can expand to the right for Pomodoro or switch to an animated calendar mode. The main window and menu bar can still show or hide the panel.

Added `ImpactGestureCoordinator`, which waits a short recognition window, groups one, two, or three impacts, and maps the result to a user-selected action. The available actions are showing or hiding the character, showing the calendar, and starting, pausing, or starting-or-pausing Pomodoro. The default mapping is one impact to show or hide the character, two impacts to start or pause Pomodoro according to its current state, and three impacts to show the calendar. Preferences are stored locally. The sensor callback records the impact separately from the action, so a single impact no longer starts or pauses Pomodoro automatically unless that mapping is selected.

Added a read-only EventKit context layer. It requests full calendar access after the user presses **Connect calendar**, taps the permission button inside the calendar widget, or invokes the three-impact calendar action. The request activates the app so the system sheet can be presented from a sensor or non-activating panel event, resets the event store after approval, shows the next event and its time, extracts an HTTP(S) link from the event URL or notes, and offers **Open meeting link**. If access was previously denied, the same control opens the Calendar privacy settings. The generated Info.plist includes both the legacy and full-access calendar usage descriptions required by the supported macOS target.

The validated sensor now starts automatically when Sieghart opens. The main window and menu bar retain a pause/resume control for testing, recovery, and machines without a compatible sensor. A failed automatic start is shown as a readable status and does not block the rest of the app.

When Pomodoro enters the focusing phase, the widget places a circular countdown with the remaining time to the right of the face, adds an animated pair of focus arms, and offers a **Finish** button. The button marks the session as completed without requiring the main window. The panel becomes sticky for the focus phase, so it remains available while the person looks toward the notch. A manual hide is still possible; hovering over the notch reveals the focus widget again.

The three-impact calendar action requests EventKit access on first use, then switches the widget into a calendar mode with an animated calendar icon and compact upcoming-event rows. When access is missing, the widget itself shows **Connect calendar**; the main window and menu bar remain fallbacks for explicit setup and recovery. The app does not label a request as dismissed unless the system reports a final authorization state; if EventKit returns without changing the state, it says that the permission sheet did not appear and offers Calendar settings.

**Why:** the notch presence is the product's primary interaction surface, as shown by the visual reference. A face-only widget keeps that surface calm, while configurable impact mappings let the user decide whether physical input should call the character, start focus, or control another local action. Calendar context is the first useful information source for the assistant and supports the future five-minute meeting warning without adding writes before permission and confirmation flows are designed.

**Design decisions:** the panel is a normal AppKit window anchored flush to the top edge and centered on the display's notch area; its custom shape has a straight top edge and rounded lower corners so it visually joins the notch instead of floating behind or below it. The fill is fully opaque black and the panel has no shadow, preventing underlying windows from bleeding through the notch surface. macOS does not provide a general public API for drawing inside the physical camera cutout, so the panel stays in the safe visible area and works on displays without a notch. It is non-activating so it does not steal focus from the current app. The hover implementation uses a bounded tracking panel instead of a global pointer monitor, avoiding the event flood that previously made the system unresponsive at launch.

**Validation:** arm64 and `x86_64` Debug builds succeed with code signing disabled, including `EventKit`, the generated privacy keys, the animated focus and calendar widgets, the gesture coordinator, automatic sensor startup, and the widget finish action. Runtime validation is pending: run the app with **⌘R**, confirm the sensor is already active, confirm the widget joins the top edge of the notch with a solid black surface, set two impacts to **Start or pause Pomodoro**, verify that the same gesture starts and then pauses the session, observe the countdown orb on the right, the focus arms, and the **Finish** button, then set three impacts to **Show calendar**, use the widget's **Connect calendar** button if the system sheet does not appear immediately, verify the upcoming-event rows, and test the link path.

**Limitations:** the widget position is a first calibration and may need per-display offsets, especially on an external monitor or a display with a different notch geometry. The bounded hover panel still needs testing on a display without a notch. Calendar access and link extraction have not yet been tested against the user's real calendars. No calendar event is created or modified in this phase. The impact cooldown and recognition window are initial values and may require separate calibration for the M3 Pro, Intel i9, and M5 Air.

**Follow-up correction — 2026-09-20:** moved the calendar authorization trigger into `showCalendar()` so every calendar reveal path requests access, and added a permission button inside the calendar widget for recovery. The request now activates Sieghart before calling EventKit, waits briefly for activation to settle, distinguishes a final denial from a request that returned without a system sheet, and opens Calendar privacy settings when needed. The generated application `Info.plist` was rechecked and contains `NSCalendarsFullAccessUsageDescription` and `NSCalendarsUsageDescription`. The notch panel now uses a solid black fill without a shadow, and its horizontal position uses the display's auxiliary top-left and top-right areas when available.

**Notch presentation refinement — 2026-09-20:** raised the widget to a window level above the main menu surface (`mainMenu + 3`) so it is composited in front of the physical notch area. The panel joins all applications and Spaces, remains flush with the display's top edge, and keeps a straight top edge with rounded lower corners. Appearance now combines a short AppKit opacity animation with a SwiftUI spring scale anchored at the top edge, creating a fluid expansion from the notch. The surface clips its content to the same notch shape and uses a 28-point lower-corner radius to match the reference proportions.

**Notch attachment correction — 2026-09-20:** photo validation showed that moving the entire panel below the camera cutout created a visible T-shaped connection, with the physical notch sitting on top of a separate rectangle. That approach was removed. The panel is again anchored to the display's absolute top edge so its full width remains behind the physical notch, while its height increases from 160 to 196 points. The bottom therefore extends farther down without separating the black surfaces. The full black surface, not only its content, uses the top-anchored spring transition so it expands downward as one continuous notch extension.

**Follow-up validation:** the universal arm64 and `x86_64` Debug build completed successfully after these changes. Runtime validation still belongs on the user's M3 Pro: use the three-impact calendar action, click the widget's **Connect calendar** button, and confirm the macOS permission sheet and the final panel geometry.

**Commit:** pending runtime validation.
