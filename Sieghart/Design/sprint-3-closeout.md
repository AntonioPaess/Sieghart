# Sprint 3 — implementation closeout

October 7, 2026. **Implementation complete; real Mac acceptance pending.** The user reconfirmed “keep it closed; I will test.” Sprint 4 has not started. No app UI, real shortcuts, microphone, sensor or system audio was activated during this verification.

## Delivered

| Area | Delivered behavior | Verification |
| --- | --- | --- |
| First run | Six initial companions, saved selection, optional local AI monitoring, offline focus | Isolated onboarding/preferences checks; production render |
| Companion / island | Shared voice panel, whole-notch click, pointer-exit collapse, crossing/keyboard approach grace, no forced focus, three sizes, six native animated companions | Native handler/state fixtures and offscreen app/menu/island previews |
| Appearance | System / Light / Dark; independent Glass switches default off; reduced transparency/motion | Persisted preference tests and production renders |
| Global shortcuts | Resident activation after red-close, system-dispatcher registration, fullscreen overlay ordering, truthful backend status | Isolated lifecycle/event fixtures; actual WindowServer acceptance remains open |
| Voice actions | Installed-app launch and English/Portuguese default-browser search, acknowledgement/cancellation in Companion | Injected actions and encoded-query tests; actual microphone acceptance remains open |
| AI dashboard | Quota/source, per-model prices/FX, current work, exact hourly/model/project/heatmap detail | Protocol/parser/pricing fixtures, production render and real read-only metadata |
| Actual charges | CSV/JSON selection, reviewed totals, exact amounts, atomic import, stable references, export and duplicate protection | New import/roundtrip/conflict/persistence checks; [format](charge-imports.md) |
| Broader history | Explicit one-year bounded local/archive scan; cancellation; retained counters during polling; cloned-session deduplication | Large-tail fixture, archive clone and more-than-80-file checks |
| Claude automatic quotas | Version 1/2 desktop history, session/week/scoped allowances, latest reading only, 30-minute freshness, no guessed resets, report fallback | Format/account-isolation/stale/invalid fixtures and local missing-source check |
| Audio | Master + at most five actual apps; native icons/device identity; real capture request path; route rebuild after output/format/helper changes | Mock permission/denial/retry/teardown and bounded PCM checks; playback acceptance remains open |

## Verified this round

- Nine isolated groups passed. They use fixture actions/hardware and never register real shortcuts or open apps.
- Signed universal `arm64` / `x86_64` build succeeded. Built-package privacy descriptions, resident-agent metadata and signature passed.
- Production app/island/menu screens rendered offscreen. The new [search](Concepts/island-companion-search-preview.png) and [data sources](Concepts/ai-data-sources-preview.png) images use illustrative data.
- Read-only installed Codex adapter returned a quota bucket. The actual local metadata reader returned 80 files, 852 counter records and zero records without a model. No prompts, account identifiers, responses or credentials were logged.
- This Mac has no fresh Claude desktop plan-history reading. The UI must say unavailable; no zero quota or reset time is invented. The desktop source describes its own signed-in account, which may differ from Claude Code.

## User Mac acceptance

Use the updated built app, not an older installed build. Launch manually from Xcode or the generated Debug package.

| Check | Steps and expected result | Issue |
| --- | --- | --- |
| Resident / fullscreen shortcuts | Reveal with Control + Option + S. Close the settings window using red close. Try again in another desktop and a different app's fullscreen Space. Control + Option + V should open listening in Companion. Check Activation's received-backend status. | SG-001 |
| Notch interaction | Click the center and both wings once while AI/timer/idle is active. Click again to collapse. Approach a control within the crossing allowance. Leaving every expanded page collapses. No first-click selection rectangle or bright top seam. | SG-002 / SG-005 |
| Actual speech | Grant microphone/speech, choose your speech language, say “open Safari” / “abra o WhatsApp”, then “search for Swift tutorials” / “pesquise receitas”. Correct app/query opens; Cancel ends capture; denied access gives recovery. Normal navigation never starts focus. | Voice acceptance |
| Actual app audio | Play media or a WhatsApp call. Enable the mixer and grant real system audio. Change app volume and mute; Master remains independent. Deny/retry, switch speakers/AirPods, enter headset call mode, unplug/reconnect. Disable restores ordinary playback. No placeholder columns; at most five apps. | SG-004 |
| First run / sources / appearance | Choose each available companion and verify persistence; accept/decline monitoring. Check chart/source values. Select appearance and each Glass switch independently. Verify reduced motion/transparency. If using Claude, enable its desktop usage menu and check a fresh local reading. | S3 acceptance |

Do not close SG-001/SG-002/SG-004 or mark Sprint 3 accepted based only on fixture results. Record the actual Mac result and any remaining failure before starting Sprint 4.

## Following scope

Sprint 4 remains system monitor, keep awake, device priorities/shortcuts and power/display essentials. Sprint 5 includes calendar/reminders, notifications, selected-folder downloads, clipboard/shelf and capture utilities. Avatar agents, file upload/email and optional GitHub remain in [Useful companions](companion-capabilities.md) after the core utilities.
