# Companion reference — Coucou

October 8, 2026. The user supplied the [animated demo](https://github.com/Louis-CFM/coucou/blob/main/docs/media/demo.gif) as inspiration after confirming that all Sprint 3 acceptance checks passed. Reference research only; no new runtime integration is delivered by this note.

## Observed and documented

- Demo frames show a compact character integrated into the notch and an expanded task view with the character, named session, execution stages and file changes. The result has more visual weight than navigation.
- The [project README](https://github.com/Louis-CFM/coucou) describes expressive pointer interactions, agent completion reactions, file drops, Mail handoff and optional task integrations.
- The [interaction specification](https://github.com/Louis-CFM/coucou/blob/main/docs/SPEC.md) coordinates shell, character and content transitions; small session indicators accompany a focused character. It also describes hover expansion and inactivity dismissal, which differ from Sieghart's confirmed interaction rules.

## Proposed application to Sieghart

| Direction | Concrete experience | Prerequisite |
| --- | --- | --- |
| Useful task companion | Show the requested outcome, current stage, result and one relevant next action in Companion. | Verified task lifecycle and result opener. |
| Coordinated motion | Animate the surface, avatar position and content as one transition; preserve matte depth and gentle movement. | Own six-character artwork, interruption handling and reduced-motion fallback. |
| File receive and carry | A dropped file gets a visible receive/carry gesture and filename; working and completion reflect actual adapter events. | File handling; upload/email adapters for the later connected workflow. |
| Primary companion and task agents | Keep the chosen avatar primary; small indicators show other real tasks and open their details on click. | Persistent task state and optional agent roles. |

Retain CRT Buddy, Arcade 1984, Minimal Spirit, Coast Buddy, Paper Pal and Ink Buddy. Opening remains click-only, hover gives feedback, pointer exit collapses and Glass remains configurable. Prioritize S4 system monitor, keep awake and audio/device essentials before connected companion workflows. The Challenge keeps an offline companion path. These are design proposals for [Useful companions](companion-capabilities.md), not new Sprint 3 requirements.

## Sprint 4 application — October 8

The new welcome and post-onboarding widget reveal use original native choreography: shell opening, delayed selected-avatar arrival, eyes opening and a soft nod, with reduced-motion fallback. No code or artwork was copied. Clipboard and editable rails remain real local tools. File/upload/email, chat connections and specialist agents are recorded after core utilities in the Sprint 4 checkpoint and Useful companions note.
