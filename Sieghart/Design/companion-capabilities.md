# Useful companions

Updated October 8, 2026. Product proposals requested by the user. These features are backlog options, not shipped capabilities. Sprint 3 is accepted; core Mac utilities remain the delivery priority. Any of the six companions can be the primary companion. Optional task roles let the other characters act as agents while retaining the same base capabilities.

The new [Coucou reference study](coucou-reference.md) informs task/result hierarchy, coordinated motion, file receive/carry gestures and compact task-agent indicators. Sieghart retains its six companions, click-only opening, pointer-exit collapse and optional Glass.

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

## User direction — A companion that follows through

The user wants practical attachment to Sieghart: a familiar companion that carries a task through several tools, with less switching between apps and fewer steps to remember. Supporting people with ADHD is an explicit product intention. The design goal is clear, resumable workflows; benefits must be checked with users rather than assumed from a diagnosis.

### Receive a file, upload it and send it

Example: drag a document onto the companion, then say “upload this and email it to Ana”. The same Companion surface keeps the file and the requested outcome visible.

1. Receive the selected/dropped file; show its filename and an expressive receive-and-carry animation.
2. Upload to the user-selected connected service and show actual progress. Retain the resulting link and access setting.
3. Prepare the email with the intended recipient, subject/body and attachment or uploaded link. Ask for only genuinely missing information, such as which Ana or which destination.
4. Show the finished message and sharing destination together. Send using explicit authorization through the user's command or final Send action. Prepare, upload and send are distinct recorded stages; no automatic send is inferred just from dropping a file.
5. Report the real outcome and let the user open the file/message. Failed or interrupted stages remain resumable without silently repeating an upload or email.

Dependencies: file handling, a connected upload adapter, email provider authorization, recipient resolution, access controls, persistent task state and cancellation/retry. This is a future product workflow, not implemented in Sprint 3. The Challenge's offline story can demonstrate local receive/carry organization without requiring email or cloud access.

### One principal companion, others as task agents

The chosen avatar remains the primary companion: it receives requests, keeps context and presents results. Other avatars can take optional, configurable roles such as files, communication, research, routines or development. A small agent indicator shows who is working and what stage it has reached; details open on click within the existing navigation.

Roles represent real tasks and adapters, not six disconnected chat tabs. Any avatar can become the principal one. A task can use one agent or several steps while the primary companion maintains one coherent status. Specialist roles do not restrict basic tools to a particular character. This is an exploration direction; role assignments, concurrency and delegation are not implemented or finalized.

### Connect existing chats

Let the user choose a supported chat connection and hand off a selected file or task from Companion. Keep the destination and current stage visible, then offer Return to chat or Open result when a real provider event confirms completion. Each connection requires a supported adapter, explicit sign-in and destination selection; local Codex usage monitoring does not grant access to arbitrary ChatGPT chats. Retry and cancellation must preserve completed stages. This is recorded after core Mac utilities, not implemented in the current Sprint 4 slice.

### Attachment through usefulness

- Let the companion remember user-chosen preferences and unfinished tasks, so it can offer a clear next step on return.
- Keep one requested outcome visible, with a brief checklist and a calm explanation of what is waiting, done or blocked.
- Offer Resume, Cancel and Undo where the action supports it. A retry should not repeat already completed external actions.
- Use carrying, listening, working and completion gestures to explain actual state, with text equivalents and reduced-motion alternatives.
- Keep optional reminders gentle and configurable. Avoid guilt, punitive streaks or forced focus when the user comes back.
- Pair personality with reliable results; expressive motion should help explain the task and strengthen familiarity.

## Expressive companion team — User direction, October 8, 2026

The user now explicitly requests a chosen primary companion and configurable specialists for email, calendar/agenda, finances, wellbeing and personal knowledge/development. These are proposed product requirements, not implemented agents or connections. Core utility acceptance still precedes the connected workflow milestone.

### One request, five optional specialists

With six characters, the chosen primary keeps one coherent conversation and task status; up to five others receive user-assigned responsibilities. Suggested roles are Communication (email/attachments), Agenda (events/reminders), Money (bills/expense organization), Wellbeing (opt-in break routines) and Knowledge/projects (selected Obsidian vault and GitHub repositories). Any avatar can fill any role, and roles can be disabled or changed. File handling is shared across roles rather than requiring a seventh avatar.

Example: “Send this report to Ana, put the meeting in my calendar and save the summary in Obsidian.” The primary keeps the requested outcome visible, delegates verified steps, and displays each specialist's real stage/result in the same Companion surface. Completed stages persist through restart; retrying a failed note/calendar stage must not resend an already delivered email. A specialist runs only while it has work; the UI does not invent five busy agents.

Prerequisites: semantic request interpretation, a persistent task/state model, per-tool adapters, cancellation, dependencies, result verification, duplicate-action prevention and connected account/vault/repository selection. The existing voice command parser and local AI-usage monitor do not provide a conversational agent runtime or arbitrary chat access.

### A shared expressive language

| Actual state | Proposed characteristic motion | Required evidence |
| --- | --- | --- |
| Preparing voice | Small expectant lean; brief preparation text | Actual permission/input preparation. |
| Listening | Cups or unfolds a small stylized ear; eyes attend to the user | Live microphone capture, with a clear recording indicator. |
| Interpreting | Thought bubbles, a curious tilt and a small head glow | A real command interpretation/planning operation; not a timer pretending to be thought. |
| Understood | Short nod or tiny hop | An understood request, even if execution is still pending. |
| Working | Role-specific gesture: carrying a file, holding an envelope, moving a calendar card | Real adapter events; show stage/counts or a spinner, never invented percentages. |
| Speaking | Eyes/body pulse with speech phrasing; optional mouth on characters that suit it | Actual spoken-response playback; transcript remains available. |
| Waiting | Holds the relevant item and presents one decision | A real missing choice, approval or unavailable source. |
| Completed | Brief hop, turn and celebratory landing | Verified task completion, distinct from merely understanding the request. |
| Failed/cancelled | Recoverable puzzled expression or quiet return | Actual error/cancel event and Resume/Retry where supported. |

Each character uses its own silhouette, palette and timing: CRT visor/antenna, Arcade pixel accents, Minimal Spirit face-only cues, Coast curl, Paper folds and Ink's capsule. Temporary ear/hand props preserve the approved minimal 2.5D family. Crossfades and body transitions must begin from the visible current pose when interrupted. Reduced-motion and quiet-intensity settings retain state text and controls. Celebration does not force the island open or obscure a current decision.

Recommended sequencing: evolve this shared state vocabulary alongside S5's real calendar/reminder/file events; implement connected specialist workflows after the required core tools and adapters are verified. This recommendation does not expand Sprint 4's acceptance gate or claim S5 has started.

October 8 follow-up implements expectant preparation, an attentive listening ear/tilt, processing dots/gaze during recognition and actual pending actions, successful hop/turn/landing, and failure shake in all six. Interrupted transitions start from the visible pose; Reduce Motion/disabled motion retains static cues. [Native motion preview](Concepts/simple-companions-voice.gif). Speaking/lip-sync, role-specific working props, agent reasoning/planning and specialist delegation remain unimplemented. Processing gestures describe actual recognition/action state, not invented thinking.

### Wellbeing feasibility and boundaries

Start with a chosen work-session break reminder. Mac activity time alone must be labeled session time, not proof that someone has remained seated. Supported motion-capable AirPods can supply head orientation/motion on macOS through [Core Motion](https://developer.apple.com/videos/play/wwdc2023/10179/); that is not a measurement of full-body posture. Explore a user-calibrated head-tilt reminder with device support checks, opt-in Motion access, pauses and local processing.

Apple Watch health/activity data needs a separately authorized companion integration. Plan an iPhone/watchOS companion and an explicit sync adapter, based on [Apple's health platform](https://developer.apple.com/health-fitness/). Keep missing/stale data visible and retain reminders without a watch. Do not invent sitting, fatigue, stress or medical conclusions from keyboard use or headphone motion. This is wellbeing assistance, with no diagnosis or prescribed treatment.

### Connected memory and projects

Plan configurable Obsidian and GitHub adapters, including MCP where the selected server/tool supports the workflow. Select the vault/repositories and available actions explicitly. Start with retrieving notes and PR/build status, then support reviewed note/task writes. The primary links each result to its source and remembers unfinished user-selected work. Email/calendar actions need their own verified adapters; connecting an MCP server does not itself implement every agent role.

### “Megabrain” Easter egg

Recognize deliberate commands such as “Megabrain active” and “ativar Megabrain” during an explicitly started voice session. A large stylized lilac brain briefly rises from the selected character, followed by a cheeky pose and smooth return. Keep it local, interruptible and compatible with motion-off/Reduce Motion. It grants no extra permissions, changes no model or account and does not claim increased intelligence. This Easter egg and its command are proposed, not implemented.

### Improvements beyond the references

- One outcome across email, agenda and notes, with resumable verified stages and a useful result opener.
- User-assigned specialist roles and distinct character gestures, without splitting the experience into six independent chat tabs.
- Personal continuity: selected-project “where I stopped” notes, task history and optional morning/return summaries.
- A calm attention policy: urgent requests, quiet background work, user-set quiet hours and a single meaningful next action.
- Optional connected wellbeing with source-aware, calibrated reminders; useful fallback without accessories.
- An editable automation preview: show the planned recipients, calendar, destination and completed steps before the user's authorized execution.

## Shared interaction rules

- Hover gives a small expression; click opens the existing Companion surface.
- Keep short status and one or two relevant actions in that surface. Details belong to the relevant tool page.
- The avatar does not start focus because an AI task or another app is active.
- Expressions always have text equivalents; reduced motion and disabled animation retain all actions.
- Any of the six can be the principal companion. Optional agent roles organize tasks; core capabilities remain available regardless of character selection.
- Each event must identify its source and expose unavailable/stale states. Avoid fabricated progress or completion.

## Already implemented in this round

The separate Voice island page and Voice launcher tile are removed. Speak, the menu command and the voice shortcut use Companion itself. Preparation, listening animation, transcript, success or failure and Cancel/Back fit the existing 620 × 240 base panel. Returning from voice does not start a timer. The user confirmed all Sprint 3 manual checks passed on October 8, including the voice acceptance checklist.

## Appearance controls

Appearance offers System, Light and Dark. Glass is off by default, with two independent saved switches: Other windows and panels, and Dynamic Island. The first controls the main window, onboarding, menu and data sheets; the second controls the expanded island. The compact island and camera band stay black. macOS Reduce Transparency overrides both switches. Offscreen screenshots illustrate layouts and palettes; native desktop refraction is not validated by those renders.

[Light appearance settings](Concepts/app-appearance-light-solid-preview.png) · [Dark settings](Concepts/app-appearance-preview.png) · [Voice in Companion](Concepts/island-companion-voice-preview.png).
