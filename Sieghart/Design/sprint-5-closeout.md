# Sprint 5 — Implementation delivery

October 12, 2026 · branch `sprint-5`.

The local Sprint 5 implementation is delivered. The signed build, isolated unit/integration checks and offscreen layouts are verified. **Physical Mac acceptance is still pending with the user.** Sieghart and Xcode remained closed during assistant verification, as requested. This is not an acceptance report for real permissions, Finder, screen capture, sharing or whole-process CPU.

## Delivered

| Area | Implemented behavior |
| --- | --- |
| Calendar and reminders | Shared app/menu/island state, calendar selection, day/week/month, selected-day agenda, next event and supported meeting links. Explicit Calendar access/recovery, local reminders, dismiss/snooze, event alert lead time and quiet hours. Gantt appears on consent, denied access and agenda surfaces. |
| Downloads | Up to five explicitly selected folders. Kernel folder/partial-file events, throttled rescans, bounded recent history, open/reveal/keep actions and reconnect. Initial files are a baseline; a vanished partial produces completion only when a new or changed readable final file is present. Size is real; percentage stays unavailable. Disabling, sleep and termination tear down owned watches. |
| File shelf | Up to forty bookmarked references, file picker/Finder drop, original-preserving removal/clear, open/reveal/native Quick Look, native share and outward file drag. Scoped access is retained only while a file surface or preview needs it. Reconnecting updates the drag URL; moved/renamed bookmarks refresh their label/path. Missing references offer reconnect. |
| File helpers | Select files or explicitly read the Finder selection, select a destination or current Finder folder, then review and confirm a move. Rename a shelf file or Finder selection through the same review. Optional configurable prepare-move, review-destination and rename shortcuts are off by default and register only with Finder in front. Literal names, conflicts, stale inputs and partial rollback are handled. Existing files are never replaced; keep-both generates another name. |
| Plain text paste | Clipboard action targets the previously selected app. Prefer its native matching-style menu; otherwise temporarily write plain text, request paste and restore the original formats only if the clipboard has not changed. Requires existing Accessibility access. Protected/oversized data and unavailable destinations are left intact. |
| Link cleanup | Review original and cleaned HTTP(S) links before copying. Known tracking fields are removed while encoded values, duplicate useful parameters and fragments stay intact. Signed links stay unchanged. |
| Disk images | Explicit DMG inspection, supported top-level app choice, destination/conflict review and confirmation. Read-only mounting, staged copy and owned cleanup; original image retained. The installed app is not automatically opened. |
| Capture | Explicit area selection/access recovery, supplied-image import without screen access, pen/box/arrow/text annotation, undo/clear, image copy/save and shelf handoff. Local Vision text/QR extraction and native color sampler with hex copy. Cancellation restores the island and leaves no active owned selection process. |
| Task cards and companions | Actual shelf/download/capture/reminder/calendar events flow through one shared hub. Toni handles files/capture, Gantt handles calendar, Sig acknowledges and the other dock members make brief supporting reactions. Deduplication, optional per-module native notifications, quiet hours and dismissible cards. New headers respect Reduce Motion and the app's motion setting. |
| Navigation | Files, Downloads and Capture in app/menu/island, launcher alternatives and configurable rails. Existing user layouts are retained. All surfaces share the same view models. |
| Existing fixes | Removed the opening's dark rectangle without changing the approved choreography. Gantt's Calendar design revised. Fixed macOS clipboard persistence: the mobile file-protection option produced owner-unreadable files on this filesystem; macOS now saves atomically with private directory/file permissions. An already unreadable old history is reported rather than silently replaced. |

Architecture remains physical MVVM: `Features/<feature>/Views` and `ViewModels`; native adapters in `Core/Services`; reused models, views, event hub and preferences in `Shared`. Permission requests and external actions occur only from explicit user controls.

## Verification evidence

- All **16 groups** of `Tests/run-checks.sh` passed: timers, voice callbacks, voice integration, interactions, companions, quotas, spending, AI activity, pricing, audio, imports, clipboard, middle click, system utilities, calendar and files/capture. The final storage/reference refinements are additionally covered by the clipboard and files/capture rerun.
- New checks use owned temporary files and injected hardware/UI adapters. They exercise native bookmarks and JSON persistence, move/rename conflicts/stale review/rollback, shelf reconnect and original preservation, actual temporary-directory event teardown, cancellation beside an old final file, download deduplication, Finder shortcut persistence/collisions/foreground restriction/review routing and passive-monitor rejection, plain-paste restoration/new-copy preservation, URL encoding, simulated DMG mount cleanup and late conflicts, actual local Vision OCR/QR and annotation export, child-process cancellation and cross-surface shared state. No downloaded executable was run.
- Existing companion checks cover all **294 character/motion pairs**, greeting/queue/docking, interruption, bilateral gaze, cached Retina artwork and reduced motion. The approved greeting and previous renderer benchmarks are retained in [the rendering checkpoint](companion-performance-checkpoint.md); those isolated benchmark figures are not whole-app CPU results.
- Final universal Debug build: `/private/tmp/sieghart-s5-final/Build/Products/Debug/Sieghart.app`. `verify-built-app.sh` checks its actual privacy descriptions, menu-bar agent metadata, signature and signed Calendar/Automation capabilities. This is a development build with an ad-hoc signature, not a notarized distribution.
- Nine local fixture previews/exports were rendered and inspected in [Validation/sprint-5](Validation/sprint-5/README.md). They exercise layout and exported pixels, not native macOS dialogs or real drag/share interactions.
- Logs: `/private/tmp/sieghart-s5-all-checks.log`, `/private/tmp/sieghart-s5-final-focused.log`, `/private/tmp/sieghart-s5-final-build.log`, `/private/tmp/sieghart-s5-preview.log`.

Reproduce from `Sieghart/`: `bash Tests/run-checks.sh`; `bash Tests/verify-built-app.sh /private/tmp/sieghart-s5-final/Build/Products/Debug/Sieghart.app`; `bash Tests/render-sprint-5-preview.sh`. SwiftUI macro compilation needs ordinary local execution; the restricted sandbox cannot start Xcode's macro server.

## Physical acceptance needed to close Sprint 5

Follow [the Portuguese test guide](sprint-5-test-guide.md). The remaining gates are the actual Calendar/notification/Automation/Accessibility/screen-access paths, Finder drag/Quick Look/share, native paste targets, real selected-folder completion and sleep/relaunch, screen selection/color picker, fullscreen interruptions, approved opening/Retina appearance and whole-app CPU/memory. No new permission request or real hardware run is inferred from a passed isolated test.

## Coverage boundaries

- Finder shortcuts are opt-in and configurable, including F2 or chosen ⌘X/⌘V chords. They release registration outside Finder and do not use a passive monitor fallback that could duplicate Finder's native paste. If macOS refuses a chord, choose another combination. Moves/renames still require review; existing Companion/Voice/Clipboard global shortcuts are retained. The physical registration/Space-transition behavior is a Mac acceptance gate.
- DMG support is an explicit local app-copy workflow. Encrypted images, nested installer packages, privileged install paths and arbitrary scripts are unsupported. If the OS refuses to eject a mounted volume, it is left mounted for Finder to eject rather than recursively deleting it.
- Capture covers selection, image import, basic annotation, local text/QR and color. Recording, scrolling capture, continuously watched screen regions and advanced media editing are later modules.
- Task cards belong to Sieghart's actual events. There is no arbitrary notification scraping or autonomous execution by the five specialists. Calendar cards retain the existing calendar notification settings instead of reposting duplicate due alerts.
- Email sending, remote upload, chat accounts, GitHub/MCP/Obsidian, Ada's news feed, autonomous specialists, on-device Foundation Models and Sieg-owned Open Finance are future integrations. No account connection or outbound message was added here.
- The three-minute offline Swift Student Challenge package and user-authored story remain a separate delivery track. This macOS development build is not the final Challenge submission.

## Reference study

Vorssaint's public source was inspected at commit `fe24c1766d568b132c1c78c554cc422381a3a17d` for selected-folder events, partial completion, shelf references, reviewed file actions, matching-style paste and capture behavior. The GPL source was not copied into Sieghart's MIT runtime. Native adapters were written for this app. See [Vorssaint source](https://github.com/vorssaint/vorssaint-utils/tree/fe24c1766d568b132c1c78c554cc422381a3a17d) and [third-party notices](../THIRD_PARTY_NOTICES.md). Local image reading uses [Apple Vision](https://developer.apple.com/documentation/vision); color selection uses [NSColorSampler](https://developer.apple.com/documentation/appkit/nscolorsampler). Existing Coucou-derived greeting timing keeps its MIT attribution.
