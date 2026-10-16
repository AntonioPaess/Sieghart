# Ada, Sig and shared local intelligence

October 13, 2026. User-requested product direction. This document records the direction and remaining slices. The October 13 follow-up implements the initial session room and provider chat adapters described in [Ada room tests](ada-room-test-guide.md); Foundation Models inference and cross-worker orchestration remain proposals.

## Responsibilities

Sig remains the fixed principal and organizes one requested outcome across the app. Ada owns code, GitHub, tech/AI information, coding-agent activity and its token usage/API-equivalent spend. Elinor owns the user's financial organization; Toni owns files and communication. A coding cost display does not transfer control of bank finances to Ada.

### Sig with local intelligence

- Turn a spoken or typed intention into a short, editable next-step proposal, such as opening the chosen notes and starting a ten-minute focus session.
- Identify which specialist/tool can handle the request and ask for genuinely missing details.
- Capture a brief interruption note: chosen project, completed steps, where the person stopped and what to do next.
- On return, show that continuation point and offer one Resume action.
- Condense the specialists' actual results into a calm update with completed, pending and blocked steps.

These are design goals for reducing steps to remember and context switching. Actual tool state comes from the app's adapters, not a model's assertion that something happened. Sig's model proposes a plan; the execution layer validates arguments and reports the result.

### Ada's developer workspace

- Keep the selected project, branch/worktree, task, attached context and provider session together.
- Convert a large development request into a small plan, explain selected documentation or a supplied error, and offer short learning material drawn from included/selected references.
- Display coding workers' actual stages: waiting, working, running a check, blocked, cancelled or completed. Only active tasks have busy characters.
- Summarize a patch/check outcome and retain a clear next step after interruption.
- Give each task a return link to its session, terminal, repository or result. GitHub authentication and chosen repositories remain a separate adapter.

## The mini agent room

Ada is the technical coordinator. Workers are attached to real session/task IDs and chosen projects. Selecting one opens its concise status, completed work, current blocker and result. Pausing/cancelling/continuing is routed through that worker's provider adapter and reflected only after confirmation.

Communication between providers would use Ada's explicit task/message queue, correlated sender/destination IDs and replies. Delivering a message is distinct from the recipient acting on it. Worktree ownership and dependencies prevent two workers from silently editing the same checkout. Start with a single coding executor, then add collaboration after its lifecycle is reliable.

Keep this view lightweight: cached portraits/compositor movement for waiting workers, one short foreground reaction for important events, no continuously running 3D scene for every desk. Reduced Motion keeps text and status sufficient. Show one useful decision rather than a wall of simultaneous notifications.

## Local and connected model routing

The app can share one provider-routing service, while each character has its own responsibilities and selected context. Sig/Ada do not need separate permanently loaded models. Bound generation and cancel superseded requests. Speech recognition stays in the voice adapter; the language model receives its transcript rather than replacing microphone capture/transcription. A switch to a network-backed provider requires a configured connection and visible destination; an offline failure does not silently escalate to the cloud.

Apple documents local text generation, summarization, extraction and classification. Its on-device guidance lists code creation and logical reasoning among unsuitable tasks. Ada's local programming explanations therefore need their own evaluated examples; local availability is not evidence that a full coding-agent fallback will work. Included reference lessons and deterministic tools remain available when inference cannot answer. Device/region eligibility and model readiness must be checked. [Apple capability and availability guidance](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models).

The current framework also supports other local and server model providers. Keep the selected provider and OS/API availability explicit; using Foundation Models as an interface does not imply that every provider runs on device. [Foundation Models model support](https://developer.apple.com/foundation-models-framework/).

### Codex integration path

The official Codex SDK can start, continue and resume local threads. App Server provides richer clients with session/history access, approvals and streamed task/tool events; its documentation labels the app-server command/WebSocket transport experimental and unsupported for production workloads. Prototype the chosen interface before making it a released dependency. A worker's session history is not an automatic connection to every ChatGPT conversation. [SDK](https://learn.chatgpt.com/docs/codex-sdk), [App Server](https://learn.chatgpt.com/docs/app-server).

### Claude integration path

The Claude Agent SDK offers an embeddable Claude Code runtime, sessions, tools, streaming and subagents. A Swift client could communicate with an owned TS/Python helper. Anthropic's documentation requires prior approval for a third-party product to offer claude.ai login or its limits; the proposed distributable adapter starts with supported API credentials. Local Claude Code session access is separate from ordinary Claude web chats. [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview), [session storage](https://code.claude.com/docs/en/agent-sdk/session-storage).

Claude Code documents local cross-session messaging; this supplies one Claude-to-Claude path. Ada-to-Codex/Claude coordination still needs Sieg's own adapter and verified message lifecycle. [Cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging).

## Proposed implementation order

1. Deliver consistent UI ownership: Ada on AI activity, Toni on files, Sig as principal. This correction is implemented; native Mac acceptance remains with the user.
2. Build Sig's small local intent/continuation slice, with structured outputs, fixed tools, cancellation and unavailable-model recovery.
3. Add Ada's selected-context learning/workspace and one officially supported coding executor. Preserve resume and result identity before supporting multiple workers.
4. Add the event-driven room and cross-worker messaging, with actual completion/approval states.
5. Add configured GitHub and optional news adapters. The Challenge path keeps included offline tasks/material and requires no external account; model-unavailable recovery also remains useful offline.

## Architecture fit

Keep the requested Features/Core/Shared organization: Ada/Sig feature views and view models; provider/process/tool adapters in Core services; shared task state, context references and reusable components in Shared. The current usage monitor observes activity counters; it is not a coding-agent execution/orchestration runtime. The specialist UI ownership change does not start agents or inference.
