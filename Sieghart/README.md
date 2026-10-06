# Sieghart

Native macOS SwiftUI companion with a configurable notch island and local Pomodoro timer.

The **Swift Student Challenge** is the primary product goal. The `.xcodeproj` is the macOS development base. The [repository overview](../README.md#swift-student-challenge) records the offline, three-minute story and submission milestone. Real sensor interaction remains a goal; compatibility with the accepted playground destination needs validation.

## App and notch

First launch shows a two-step onboarding: choose one of all six avatars with its name/personality, then choose local AI monitoring. Finish saves both preferences. Existing avatar choices are preselected. The offline companion/focus journey works when monitoring is declined. **Review introduction** can revisit the flow; **Appearance** changes the avatar later.

- **Overview** shows the current session and completed count.
- **Focus** opens a dedicated tab in the app. It uses the same configuration editor as the widget: focus 5–60 minutes, short breaks 5/10/15, long breaks 15/20/30, rounds 2/4/6/8, and automatic breaks. Draft changes apply when starting a new session.
- **Activation** records separate companion and voice shortcuts, controls hover, and exposes optional impact mappings.
- **Appearance** offers six companions in a three-column gallery: CRT Buddy, Arcade 1984, Minimal Spirit, Coast Buddy, Paper Pal, and Ink Buddy. Selection saves immediately and applies throughout the app and notch. Small, Medium and Large expanded widget sizes, timer density, character motion, and reduced motion are configurable. Compact height always follows the physical camera cutout. macOS Reduce Motion is always respected.

Normal reveal opens the selected avatar beside a contextual message, session time, and completed count. The user-approved Simple Companions family is drawn with native paths: lilac CRT square, amber pixel silhouette, floating eyes, seafoam pebble, folded diamond and charcoal capsule. Numeric eye/shape parameters interpolate blinks, gaze and moods; subtle breathing, listening pulses, nods and squash/stretch add movement. All six keep their stable saved identities. Native renders also supply the selected menu-bar icon. Legacy sprite sheets are archived in the repository and excluded from the app bundle.

The first three quick touches produce a happy expression and gentle hop, the fourth brings a grumpy shake, and the fifth sends the companion to sleep. One more touch wakes and stretches it. Each reaction has a short written response. Sleep lasts until another touch; taps separated by more than three seconds start a new burst. Custom interactions retain keyboard and VoiceOver actions with a rounded focus indicator, avoiding the native rectangular mouse focus ring.

Starting a session tucks the widget into a small island. Its height matches the physical camera cutout exactly; it grows horizontally, leaving the camera area clear. Displays without a notch use a 36-point island. The companion strolls occasionally in the free lateral space. During the final 30 seconds it appears beside the countdown, nudges the digits, and shows “Almost!”. Hover gives a visual highlight; only a click expands controls. Leaving any expanded page, including AI, tools, setup and voice, collapses it after an 800 ms crossing allowance. Keyboard reveals allow four seconds to reach a control, and entering cancels that timeout. Leaving voice also cancels capture. Explicit shortcuts and impacts remain available. Impact reveal also opens the companion from the compact state. Native panel bounds are controlled explicitly; the hosting view cannot retain an earlier view’s size constraints.

The compact island and camera strip use opaque sRGB black. Expanded pages use native glass/behind-window blur and dark translucent cards, with an opaque Reduce Transparency fallback. The moving contour keeps content at a stable layout. Physical camera glass and the display can still differ in apparent black level. Walking, nudging, bouncing, and other motion pause when character motion is disabled or Reduce Motion is enabled.

The menu shares the app’s dark palette, rounded controls, selected avatar, session card, progress bar, and voice shortcut hint.

The widget and hover zone are nonactivating floating panels with `canJoinAllApplications`, `canJoinAllSpaces` and explicit `fullScreenAuxiliary` capability. Native panels preserve their requested camera-band frame rather than being constrained to the menu-bar safe area. They restore ordering when the active Space or application changes, including full-screen apps, without activating Sieghart or reopening a dismissed companion. This follows [Apple’s overlay collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications). Full-screen transitions and hover behavior still need a physical Mac check.

A saved or previously announced completion never reopens on hover, navigation or relaunch. Every newly completed interval emits a separate completion event. The widget expands with a bouncing avatar, orbiting sparkles, and a clear completion message, including when a break starts automatically. After five seconds it tucks away if the pointer is outside; hovering keeps the message available. The break countdown continues during this announcement. Manual Finish offers a break action. Completed breaks invite the next focus session.

Timer deadlines, paused state, interval type, configuration, rounds, and completed count survive relaunch. Focus counts once; breaks never increase that count. Long breaks follow the last round. Expired sessions finish once after relaunch and wait for the user before starting another interval.

## Shortcuts and voice

The companion defaults to **Control + Option + S**. Voice defaults to **Option + Command**, pressed and released. Record any key combination in Activation; modifier-only chords are saved on release. Escape cancels recording. Bindings persist independently, can be disabled, and cannot use the same chord. Existing companion shortcut choices migrate automatically.

Regular key combinations use Carbon hotkeys. Modifier-only shortcuts prefer a listen-only CG session event tap with Input Monitoring access. Existing Accessibility access can instead use local/global AppKit monitors. Only one grant is needed; the permission button requests Input Monitoring only when neither grant exists. The session tap runs in common run-loop modes, reenables after interruption and also routes regular-key combinations even if Carbon registration succeeded, with a per-action gate preventing two backends from toggling twice. Activation offers the permission button and displays availability. Using a regular key or an extra modifier suppresses a modifier-only trigger. No keyboard text is recorded or logged.

Leaving a shortcut recorder cancels unfinished capture and restores activation. Healthy registrations stay installed after app and Space changes, wake, display wake and unlock. These transitions clear stale modifier state and check health; only abandoned recording, permission changes or failed setup cause registration changes. Carbon installs its handler on the dispatcher target. A two-second health check observes permission and secure-input changes and retries failed setup without changing the saved bindings. The intermittent failure report remains tracked in [SG-001](BUGS.md) pending physical Mac validation.

Voice starts explicitly through its shortcut, Speak, or the microphone button. Choose English or Portuguese. The app requests microphone and speech access, listens for up to ten seconds, and automatically executes a supported local command after recognition ends or a short pause. Capture stops before executing. Cancel remains available; the microphone is off while idle.

Supported intents include starting focus with a valid duration, pause, resume, finish, reset, start break, show, hide, configuration, and AI limits. A successful command gets a nod, green checkmark, and “Got it.” message. Negation, conflicting actions, and unsupported durations are rejected. This is a bounded local command interface; open-ended conversation and launching other apps remain future work. On-device speech is preferred when supported, but language and system availability can require Apple services. The timer and core interaction work independently of speech.

Speech authorization uses a Sendable callback bridge. Audio tap writes are serialized through a thread-safe feed that closes on teardown. Recognition results cross to the main actor as primitive text and status values. The signed target retains its Hardened Runtime Audio Input entitlement.

Impact gestures are off by default. Enabling them activates the experimental accelerometer reader and configurable one/two/three-impact mappings. Availability depends on Mac hardware.

Calendar is temporarily hidden. `CalendarContext.swift` remains for later repair; saved Calendar impact mappings fall back to revealing the companion.

## AI adapters

`AIUsageModel.startMonitoring` runs independently of whether the AI panel is open. With saved consent, installed Codex/Claude Code detection runs at most once per minute. Cached local lifecycle metadata refreshes nominally every five seconds; quota/counter work runs on the minute cycle and quota requests coalesce for five minutes. Codex account activity refreshes every five minutes. Requests can delay a polling cycle. Disabled providers are removed from displayed activity; disconnect also disables automatic reconnection. In-flight counter results are discarded after disconnect.

Codex access uses `account/rateLimits/read` and `account/usage/read` through the installed CLI app server and existing sign-in. Requests time out after twelve seconds. The app never starts a model turn or resets a quota. Percentages show **remaining** usage, and window names come from returned durations. Expired/missing values remain unavailable. Credentials stay within Codex. Account activity supplies dated daily buckets and a reported streak when available; failed refresh preserves a visibly dated last successful reading.

Numeric counters and activity metadata come from recent `.codex/sessions` and `.claude/projects` JSONL files. Discovery is bounded to 5,000 candidate files and processing to 80 recent files/provider. Counter parsing reads the final 2 MiB. Activity also inspects the initial 64 KiB for project metadata. When a recent Codex turn begins before the tail, a cached, bounded reverse search can inspect up to 256 MiB of older lifecycle/context records. Unchanged files are not reparsed on every poll. Only timestamps, counters, model, project basename and lifecycle are retained; no prompt, response, tool arguments or credentials are retained or logged.

Codex cumulative counters/cloned rollout IDs and Claude streamed message IDs are deduplicated. Cache and reasoning are not added twice; Claude cache creation is accounted for separately in estimates. A recent modified file alone is not proof of active work: start/completion events govern the badge, with a five-minute freshness limit. This is **partial local history**, not full account lifetime usage.

The shared dashboard provides quotas, spending, current work, 24 hourly bars, exact model/project counts and a 13-week activity heatmap. Hover/select hourly bars for immediate range/input/output/cache/value detail, or a day for its exact dated count. Summary emblems and provider choices follow usage evidence rather than mere installation. Older model context is recovered for completed histories as well as active work, without relabeling earlier counters with a future context. Account daily activity is used when supplied; otherwise the heatmap has the partial local source label. Missing days are marked **No record**. Active work appears beside the selected avatar in the compact island and opens the complete AI panel, while preserving active focus. The island retains the camera gap and physical notch height. [Dashboard preview](Design/Concepts/ai-dashboard-preview.png) and [onboarding preview](Design/Concepts/onboarding-preview.png) use labeled sample fixtures in production views.

The local ledger holds dated subscription/API charges separately in USD and BRL. `ModelPricing.swift` loads bundled numeric provider price facts and fetches official OpenAI/Claude Markdown tables daily while monitoring is enabled. Valid updates persist locally; changed/invalid tables retain the last good cache. Requests are bounded and time out. Standard prices are the default; a recorded supported OpenAI tier selects its table. Long-context rates apply only to a known individual request, never an aggregate. Claude cache-write duration is accounted for when logged. Unknown/internal models stay unpriced, with all their tokens retained and a ≥ lower bound for the priced portion. Optional custom averages override this explicitly. The USD/BRL reference rate is fetched from Frankfurter and displayed with its source date; a dated custom rate remains available. These requests send no local usage or account identifiers. API-equivalent value is not an invoice; billing imports remain planned. Claude individual subscription quotas have no verified automatic adapter in this release. A JSON report can supply a dated reading:

```json
{
  "capturedAt": "2026-10-05T21:00:00Z",
  "primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1791244800},
  "secondary": {"usedPercent": 40, "windowDurationMins": 10080, "resetsAt": 1791763200}
}
```

Source protocol: [Codex app server](https://learn.chatgpt.com/docs/app-server). Provider asset attribution: [third-party notices](THIRD_PARTY_NOTICES.md). User reference screenshots: [39-image gallery](Design/References/Widget/README.md).

## Verification

From the repository root:

```sh
bash Sieghart/Tests/run-checks.sh
```

The checks cover timer behavior and restoration, background speech callbacks, voice execution and acknowledgement, shortcut persistence and modifier gestures, all six native icons, deterministic reduced-motion states and continuous blink samples, persistent avatar selection, repeated-touch moods and waking, exact compact notch height, expanded-control collapse, completion announcements during automatic breaks, real quota/activity protocol fixtures, token/stream/clone deduplication, live-island transitions, long-turn metadata recovery, cache creation and onboarding persistence. They use isolated preferences and a headless controller: no app windows, sensor, microphone, permission requests, or system shortcut registration.

The generic signed macOS build covers `arm64` and `x86_64`. Physical notch fit, recording a shortcut in the UI, permissions, real microphone recognition, animation feel, and impact hardware still require a user run on the Mac.

## October 6 correction evidence

All seven deterministic check groups passed, including click-only island behavior, every expanded presentation's pointer exit, old completion suppression, persisted widget sizes, shared global/foreground event routing, long completed-history model attribution and per-model/tier/cache estimates. A universal signed build succeeded for arm64/x86_64 and its signature verified. Live public-source verification parsed OpenAI/Claude price tables and the October 6 USD/BRL quote; no account data was sent. [User regression captures](Design/References/Sieghart/README.md) preserve the four additional bug reports. Real foreground-app/Spaces shortcut delivery and physical notch behavior still require the user's Mac acceptance.

## Island presentation

`IslandChrome.swift` owns the independently authored shoulder contour, glass/blur fallback, translucent cards, local button feedback and native canvas. The canvas reserves both transition sizes, animates its contour without resizing the content, then returns the window to the settled bounds. Closing removes the page before contracting the shell. Compact/camera pixels stay black; Reduce Motion and Reduce Transparency are respected. External source code and reference branding are not part of the app or Challenge package.

All six Simple Companions retain their saved identities. Native paths morph their eye expression and gaze; body motion updates at 60 Hz, with cosine blinks/hops and spring expression changes. Reduce Motion preserves static readable states. [Production reaction stills](Design/Concepts/avatar-reactions-preview.png) and [native movement preview](Design/Concepts/simple-companions-motion.gif) are rendered offscreen; the GIF is sampled at 20 fps.


## October 6 — Click regression and three timer tools

The native activation strip now accepts the first mouse event from another app, uses the complete compact island width, and toggles expansion/collapse through one synchronous route. SwiftUI hosting explicitly accepts first mouse too; compact button labels give transparent spacing the same hit target. The strip stays above the panel only in the camera-height band. Hover highlights without expansion, and pointer exit collapses every expanded page. SG-002 remains a physical-Mac acceptance gate.

The app's Timers tab and widget offer Timer, Pomodoro and Stopwatch. Countdown duration is 1–180 minutes with presets. Stopwatch displays tenths and hours after an hour. Dates preserve running/paused state across sleep/relaunch; utility clocks never increment focus rounds. Selecting a mode changes only the selected page. Pause/reset keep the timer controls visible. Pomodoro retains its configurable focus/break rounds and completion notice.

Selective reference influence is the current design direction. Use useful glass/cards and timing interactions while retaining Sieghart's visual identity. New character studies should be minimal eye/dot/visor designs; the detailed 3D robot proposal was rejected. [Simple concept board](Design/Concepts/avatar-simple-studies.png) was approved by the user and now supplies the production native character direction. [Timer previews](Design/Concepts/timer-timer-preview.png) render offscreen.


## October 6 — Simple Companions and interaction follow-up

The full activation header spans the current island width, including its camera gap. Native hit testing treats the center and wings equally. A bounded global mouse-down fallback handles camera-area clicks routed by the WindowServer to another app; it sees only the pointer point inside this rectangle. Native windows accept first mouse and preserve their full screen-edge frame. A visible-only pointer check bridges missing camera tracking events. Keyboard reveals have four seconds of approach grace; pointer exit allows 800 ms. Entry cancels collapse; manual closure still acts immediately. Timer completion keeps its separate announcement deadline.

Global shortcut registrations remain intact across foreground/Space transitions. Carbon uses the dispatcher target. Existing authorized session/AppKit monitoring routes ordinary-key shortcuts as well as modifier gestures, with duplicate backend suppression. Both overlay panels declare full-screen auxiliary capability in addition to cross-app/all-Spaces placement. These changes are covered by isolated routing and timing checks; actual full-screen event delivery, physical camera clicks and movement still require Mac acceptance (SG-001/SG-002).


## October 6 — Companion depth and main-window design

The latest user reference retains minimal shapes while requiring visible depth. Matte gradients, soft layered shadows, a recessed CRT face and a curved ivory/coral Paper Pal fold now give the six native characters volume. Subtle gaze perspective respects Reduce Motion; this is 2.5D artwork, not a 3D character rig. The original palette and stable saved identities remain.

The main app now shares the glass treatment across Overview, Timers, grouped Activation preferences, Appearance, AI limits and onboarding. Overview reflects the active clock and keeps focus explicit. The compact island no longer draws its colored hover contour or native edge: feedback is a small character reaction on the unchanged black shell.

[Main-window preview](Design/Concepts/app-overview-preview.png) · [Appearance](Design/Concepts/app-appearance-preview.png) · [Depth](Design/Concepts/simple-companions-depth-preview.png) · [Borderless compact hover](Design/Concepts/compact-hover-preview.png). Production views are rendered offscreen with illustrative data; no app window, real shortcut, sensor or microphone was started. SG-001/SG-002 remain physical Mac acceptance checks.
