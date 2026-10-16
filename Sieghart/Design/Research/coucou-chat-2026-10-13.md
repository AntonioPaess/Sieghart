# Coucou chat reference and Ada's room

October 13, 2026. Source inspected locally at `71b773f08101237e1ec950efdaee17a626c830e6`. This is source analysis, not decompilation of a shipped app. Repository comments/configuration were treated as reference data.

## How Coucou puts chat in the widget

- `NotchBuddy/Sources/App/IslandViewContent.swift`, `PromptView` around lines 1288–1470: a native SwiftUI conversation list, context chip, model picker, input and Send button. `AppState.chatHistory` is the displayed conversation. It is not a browser view of ChatGPT or Claude.
- `ClaudeService.swift`, `chat`/`chatOpenAICompatible` around lines 244–478: the service keeps a separate multi-turn provider message array and performs HTTP API calls. Anthropic uses Messages; compatible providers use Chat Completions. Authentication is API credentials saved by that app, not account-wide chat scraping.
- `LocalChat.swift`, `streamChat` around lines 145–216: SSE parsing accumulates response text, publishes visible text at roughly 15 Hz and sends a final update. This prevents each token from rebuilding the UI. The examined Anthropic/OpenAI/Google branches use complete replies; not all providers stream in that snapshot.
- `IslandWindowController.swift`, around lines 190–204: the nonactivating panel becomes key in prompt mode, so keyboard input reaches its fields. Height calculations around 1319/1425 cap the chat surface and leave the conversation scrollable.
- Existing dropped-file context can be rendered in the same chat. In this snapshot, context is sent only on the first turn; provider support differs. That restriction should not be copied into later attachment work.

## Separate integration for coding-agent activity

`HookServer.swift` listens on a local Unix socket, processes session/turn/tool/permission/stop events, and holds pending permission requests for a widget response. `PillSessionRegistry.swift` tracks actual overlapping sessions per integration. `PhoneLink/TurnRecorder.swift` reconstructs turns from those events. These are different paths from the direct model chat.

This explains both experiences: a conversational assistant inside the notch and notifications/approvals for coding sessions. It does not establish that Coucou can edit every existing ChatGPT website conversation.

## What Sieg implements in this slice

Reuse the interaction: session selection, transcript, composer, streaming and pending decisions inside the same native panel. Keep per-session drafts and bounded transcript excerpts. Make the chat panel key and keep it visible while open. Cached portraits and throttled delta delivery keep chat text independent from SceneKit renders.

Use provider interfaces instead of copying Coucou's terminal hooks: Codex App Server for listing/reading/starting/resuming/interrupting supported local sessions; the official Claude Agent SDK for local session browsing, query/resume, streamed messages and tool decisions. Activity is authoritative only for attached runs. Existing sessions in other terminals remain explicitly unattached until continued here; no inference from process presence or elapsed time.

October 14 follow-up: the room now selects one provider conversation and displays Ada with its reported nested workers in a shared office. Child Codex chats can be opened where the provider exposes a thread; Claude task activity returns to its parent chat. The room does not orchestrate dependencies between workers. Background terminal hooks, direct generic model chat, Foundation Models, additional providers, file attachments to chat and cross-provider task queues are separate next slices.

## Sources

- [PromptView](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandViewContent.swift)
- [Provider service](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/ClaudeService.swift)
- [Local streaming](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/LocalChat.swift)
- [Agent hook server](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/HookServer.swift)
- [Codex App Server](https://learn.chatgpt.com/docs/app-server)
- [Claude Agent SDK TypeScript API](https://code.claude.com/docs/en/agent-sdk/typescript)

Coucou source is MIT, © 2026 Louis Raillé. This slice contains independently authored Swift/JS glue and Sieg artwork; the existing MIT attribution remains in THIRD_PARTY_NOTICES.md. No Mochi art/sound asset is included.
