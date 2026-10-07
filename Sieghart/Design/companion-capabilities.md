# Useful companions

October 7, 2026. Product proposals requested by the user. These features are backlog options, not shipped capabilities. Complete the core Mac utilities and their acceptance checks first. All six companions should offer the same abilities; their expressions, motion and palette supply personality.

## Recommended starting point

Combine **task handoff** and **contextual quick actions**. A task produces an actual event, the companion expresses it quietly, and clicking offers a useful next step. It should be possible to understand and act within a few seconds, without opening a chat transcript or starting a focus session.

| Option | Concrete experience | Events and dependencies | Boundary |
| --- | --- | --- | --- |
| Task handoff | The avatar works quietly while an AI task or download is running, celebrates completion and offers Open result, Show file or Return to task. A failure offers the relevant details. | Current AI lifecycle plus a verified task/result opener; downloads after the folder watcher exists. Build results need a separate adapter. | No completion based on elapsed time alone; no automatic island expansion. |
| Contextual quick actions | Clicking the avatar offers the actions that fit the current tool: resume a paused clock, change output to AirPods, mute an app or keep the Mac awake for a chosen duration. Voice remains in this same Companion panel. | Real timer/audio state and validated actions; keep-awake follows S4. | The user triggers every action. Saved shortcuts and mouse use remain alternatives to voice. |
| Return to your work | Before leaving, save a short local “where I stopped” note attached to a selected project. On return, the companion shows that note and offers to open the relevant app or task. | Explicit user notes, local storage, app launcher and task links. | No reading arbitrary screen contents or silently recording conversations. No project is invented from the foreground app alone. |
| Meeting companion | A compact avatar shows the selected input/output device and verified mic mute state. Clicking opens audio controls; optionally remind the user to restore music volume when a known call ends. | Verified audio device/mute state. Reliable call start/end detection needs a supported app event adapter. | Never infer microphone permission from a toggle or mute a call without user action. No analysis of recorded speech for call detection. |
| Gentle routines | User-selected reminders for water, eyes or a stretch get a short expressive gesture and Dismiss/Snooze. Quiet hours and per-reminder opt-in keep it calm. | Reminder scheduling, persistence and notification preferences after S5. | No forced focus, unsolicited interruptions or activity surveillance. |

### Optional GitHub later

A useful developer option is to watch **selected repositories** for a requested review, failing check or completed build. The companion expresses the event; clicking opens that exact PR/run. Start read-only, with separate sign-in and repository selection. Respect offline, revoked access and deduplication. This is not enabled or implemented, and does not delay system monitor, keep-awake, audio, calendar or downloads.

## Shared interaction rules

- Hover gives a small expression; click opens the existing Companion surface.
- Keep short status and one or two relevant actions in that surface. Details belong to the relevant tool page.
- The avatar does not start focus because an AI task or another app is active.
- Expressions always have text equivalents; reduced motion and disabled animation retain all actions.
- Keep capabilities equivalent across the six characters. Customization changes personality rather than access to features.
- Each event must identify its source and expose unavailable/stale states. Avoid fabricated progress or completion.

## Already implemented in this round

The separate Voice island page and Voice launcher tile are removed. Speak, the menu command and the voice shortcut use Companion itself. Preparation, listening animation, transcript, success or failure and Cancel/Back fit the existing 620 × 240 base panel. Returning from voice does not start a timer. Voice recognition and actual microphone/app-launch behavior still require user acceptance on the Mac.

## Appearance controls

Appearance offers System, Light and Dark. Glass is off by default, with two independent saved switches: Other windows and panels, and Dynamic Island. The first controls the main window, onboarding, menu and data sheets; the second controls the expanded island. The compact island and camera band stay black. macOS Reduce Transparency overrides both switches. Offscreen screenshots illustrate layouts and palettes; native desktop refraction is not validated by those renders.

[Light appearance settings](Concepts/app-appearance-light-solid-preview.png) · [Dark settings](Concepts/app-appearance-preview.png) · [Voice in Companion](Concepts/island-companion-voice-preview.png).
