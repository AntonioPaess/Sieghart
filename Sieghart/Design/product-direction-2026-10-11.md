# Sieg — practical value, local intelligence and the Challenge

October 11, 2026. Product direction requested by the user. Sprint 5 remains the current implementation sprint. This note records proposals; it does not close Sprint 5 or claim specialist agents/local AI are implemented.

## Purpose

October 12 update: the [consolidated map](sieg-feature-map-2026-10-12.md) records the latest scope. The user wants bank connections offered by Sieg's own Open Finance flow, rather than a Pierre account connector. The complete Challenge journey, including use after onboarding, stays offline with included resources and labeled sample data. This update does not implement integrations or close Sprint 5.

Help a person who feels overwhelmed find one manageable next step, start it and resume it after an interruption. Sig is permanently the main companion and orchestrator. Rita, Ada, Gantt, Elinor and Toni keep their identities and future specialties. The user has accepted the latest greeting choreography.

Timers, clipboard recovery, voice shortcuts and the calendar slice provide useful building blocks. The task planner, persistent task resumption, contextual voice assistant and real specialist execution still need implementation. The aim is organizational support whose value is measured with users, not a clinical treatment claim. [NIMH](https://www.nimh.nih.gov/health/publications/adhd-what-you-need-to-know) describes difficulties with organization, time management, remembering tasks and completing projects; it does not establish efficacy of Sieghart.

## Reference opportunities

| Reference | Verified useful patterns | Sieg proposal |
| --- | --- | --- |
| [Coucou](https://github.com/Louis-CFM/coucou) | File drop/context/Mail handoff, real agent state and approvals, exact-result/terminal links, GitHub PR/review/CI context, integrated voice, setup-free demo. | Carry one requested outcome through stages; show what is waiting, done and resumable; animate the responsible specialist from real events. |
| [Vorssaint](https://github.com/vorssaint/vorssaint-utils) | Searchable command bar, file shelf, snippets, scratchpad, offline screen text recognition, optional modules and scoped permissions. | A contextual capture tray and a Now/Next/Later view; expose a few relevant tools per task and retain user control over visibility. |
| [Clicky](https://www.heyclicky.com/) | Spoken help using explicitly requested screen context, drawn guidance, conversation versus agent execution. | Natural requests, optional selected context and one instruction/action at a time within Companion. Preserve local task memory. |
| [OpenJarvis](https://github.com/open-jarvis/OpenJarvis) | Public assistant framework: orchestration, persistent memory, scheduled work, MCP tool adapters, engine interfaces and a Foundation Models source adapter. | Study execution contracts for Sig and the specialists; keep native Swift services and evaluate selected backend integration separately. |

The [OpenJarvis reference note](Research/openjarvis-reference-2026-10-11.md) records reviewed sources and integration boundaries. Its source is Apache 2.0; its runtime has not been installed, tested or integrated into Sieg.

Coucou's application source is MIT with separately protected branding/art; Vorssaint is GPL-3.0-or-later. Source inclusion must follow the actual license and attribution. The current brief uses product patterns rather than importing new runtime code from either reference. Clicky's [trust page](https://www.heyclicky.com/trust) documents cloud processing; a local organization engine is a meaningful direction for Sieg.

## ADHD-oriented flows to build and evaluate

| Need | Concrete experience | Intended owner |
| --- | --- | --- |
| Starting an overwhelming task | Capture a short brain dump; suggest at most three manageable steps; display one first action with a chosen duration. | Sig / relevant specialist |
| Remembering where work stopped | Save the current step, selected file/link and a short continuation note; offer Resume on return. | Sig |
| Maintaining focus | Pomodoro, chosen focus duration, pauses/resumption and a visible next step. | Sig |
| Seeing commitments | Keep the next chosen calendar event visible; offer a planned transition. | Gantt |
| Recovering a thought or item | One capture action for text, clipboard content and selected file references, followed by a searchable local tray. | Sig / Toni |
| Taking breaks without disruption | User-selected reminders, quiet hours, snooze and restrained reactions; no punitive streaks or guilt. | Rita |
| Finishing a practical action | Carry a selected file into a prepared message with the destination/result visible and explicit send authorization. | Toni |

Ada can connect a selected code task to a PR/build result; Elinor can organize user-supplied resource/bill reminders. Their future roles must resolve actual tasks rather than launching unrelated utilities. These are not currently active services.

Evaluate time to the first useful action, success resuming after a planned interruption, app switches needed, and perceived effort. Include participants who use different input/accessibility options. Benefits remain hypotheses until validated with users.

## News and focus follow-up

User direction, October 11: one avatar should curate principal tech/AI news; another should own focus/Pomodoro, with Sig explicitly acceptable. Phone distraction blocking is future work.

- **Ada is the proposed news owner**, extending her code/technology role. Offer a short finite briefing (for example, up to five items) with configurable topics, sources and delivery time. Each item includes a source link, publication date and a brief explanation of relevance. Deduplicate stories and retain read/save-for-later state. Fresh news comes from real feeds/adapters; local AI may summarize fetched material, not invent current events.
- **Sig is the proposed focus owner**, coordinating Pomodoro, focus duration, pause/resume and returning to the current task. Gantt retains calendar/commitment responsibility; Rita retains wellbeing/break reminders.
- The news briefing respects focus and quiet hours. Hold optional news until a chosen break or session end; do not introduce an endless feed or attention-seeking alerts.
- **Future phone blocking:** let the user choose distracting apps/sites and whether a focus session restricts them. The phone platform and cross-device transport are not yet selected. For iPhone, investigate a companion app with Apple's [Screen Time frameworks](https://developer.apple.com/documentation/screentimeapidocumentation), individual authorization and the required [Family Controls capability/distribution entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement). This supports investigating app/site restrictions; full-device locking from the Mac is not a validated capability.
- End/cancel/revocation must have defined restriction cleanup. A phone session needs an independent expiration/recovery policy if the Mac disconnects, sleeps or quits. The future design needs validation on the chosen platform before implementation claims.

These additions are backlog directions, not new Sprint 5 exit requirements or shipped news/phone-control features. The mandatory offline Challenge journey continues to work without live feeds or a connected phone.

## Foundation Models proposal

Use Apple's [Foundation Models framework](https://developer.apple.com/documentation/foundationmodels) for short text understanding, structured task steps, extraction and tool selection. Use the relevant Speech APIs for transcription, Vision/Accessibility for approved textual context, and native/connected adapters for actual actions. A language model call does not itself provide speech capture, arbitrary screen vision, calendar authority or email delivery.

Start with one shared task engine and request-owned sessions; avatars specialize instructions/tools. Do not run six continuously generating models. Bound context and work to the requested task, preserve cancellation and stale-result handling, and keep expressive state aligned with execution.

Check [model availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum) and OS compatibility. Eligible hardware, Apple Intelligence activation and a ready model cannot be assumed. Keep an offline non-model path for planning and the judging demonstration. Network services such as email delivery and GitHub remain connected capabilities even when the language interpretation is local.

Foundation Models has not yet been added to the current app.

## Challenge direction

As of this note, the [2026 policy](https://developer.apple.com/swift-student-challenge/policy/) sets the deadline at February 28, 2026; that edition is closed. A later edition's published rules need revalidation. The current [requirements](https://developer.apple.com/swift-student-challenge/eligibility/) specify an app playground `.swiftpm` in a ZIP of at most 25 MB, offline judging, an experience within three minutes and English content. On-device Apple Intelligence is expressly permitted by the 2026 policy.

The repository is currently the macOS development base, not a finished submission package. Desktop/global services and a physical notch must not be prerequisites of the judging path; validate the actual destination and provide a self-contained Companion scene. Login, real email, network, microphone permissions and model downloads cannot be required to complete that path. Label sample material honestly.

Proposed three-minute experience, pending the user's storytelling:

1. **0–35 s:** meet the team and understand the purpose during the approved greeting.
2. **35–80 s:** choose an example of feeling overwhelmed; reduce it to a first manageable action.
3. **80–120 s:** start a short focus interaction and save a useful continuation point.
4. **120–160 s:** interrupt and resume; recover the right file/note through Companion.
5. **160–180 s:** show the outcome and explain the local/private approach. An optional model demonstration has a complete offline fallback.

This is a product proposal, not an implemented or timed acceptance flow. Keep replay/skip, Reduce Motion, VoiceOver and keyboard/typed paths. The judge should experience a useful transformation and understand the individual contribution. Apple's [selection criteria](https://developer.apple.com/swift-student-challenge/apply/) emphasize innovation, creativity, social impact or inclusivity; no implementation guarantees an award. Disclose AI assistance and third-party use, demonstrate personal technical understanding, and write the required essays personally as specified in the policy.

## Priority

1. Complete Sprint 5's calendar/reminders, notifications, selected-folder downloads, file shelf, helpers/capture and acceptance.
2. Validate display-quality improvements at the real widget sizes; refine materials/lighting only through inspected previews, preserving the approved animation.
3. Implement task capture, one next step and persistent interruption/resumption.
4. Add bounded Foundation Models interpretation and contextual voice.
5. Build and time the offline Challenge package; later integrate external agent/email/MCP workflows as useful extensions.
