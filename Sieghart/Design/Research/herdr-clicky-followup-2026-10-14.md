# Ada room follow-up: Herdr, Coucou and Clicky

October 14, 2026. User reported that Ada should open her room on click and that the Send arrow did not react. The screenshots also introduce Clicky's activity/navigation pattern. The previous constraint remains: no agent-launched Sieg/Xcode, provider inference, microphone, hooks, or real terminal operations during verification.

## Reproduced code paths and corrections

The room's Send arrow used a custom style that did not visually distinguish disabled state. `canSend` included provider connection; pressing a disconnected arrow could never reach an error/reconnect handler. Session selection also cleared the notice. The correction preserves notices, shows disconnected state beside the selected conversation, makes a nonempty draft eligible for an explicit reconnect-and-send, and reuses refreshed session metadata after reconnect. Failed sends retain the draft.

The old Codex adapter requested full inline history from both `thread/read` and `thread/resume`, then assumed `thread.turns` was the transcript. Current official documentation and installed CLI schema deprecate that hydration for paginated threads. It now reads metadata, pages stored turns/items and resumes with `excludeTurns: true`. This avoids loading all prior tool output simply to continue a chat. These are verified faults in the old implementation; the provided screenshot alone does not establish the exact provider/process failure from the user's run.

The user clarified that the chat should copy Coucou directly, Herdr should be an architectural reference rather than a connector, and the room should depict agents at work. The optional connector and the earlier compact-card room were removed.

The native single-line composer updates its draft for every edit and sends on Return or the same arrow action. Send clears the field and inserts a provisional user bubble immediately; a provider user-message event replaces it without duplication. Rejected sends preserve newer text. The chat's card geometry, bubbles, spacing, circular 28-point arrow and Markdown rendering are adapted directly from Coucou under MIT with source attribution. Provider/runtime identity remains visible; the existing official Codex/Claude adapters remain the integration.

Ada routes to the room on click. The conversation picker selects a shared office containing Ada and the agents in that conversation's runtime tree. The five reusable 2D worker silhouettes cycle through incoming agents, and colors remain stable for each runtime ID. Workstations show reported working/waiting/blocked/completed cues. Small typing movement runs only for reported Working agents at about 1 Hz. Selecting a child workstation opens its chat when the provider exposes one; the Room tab returns to the desks. Pointer departure and automatic timer completion preserve the open chat; choosing another widget page restores normal dismissal. Team is removed from the tools and tool options, including migration of old saved slots.

## Herdr reference

Source checkout inspected: `6521382dbed36f2d001417108149c338aee116ea` at `/private/tmp/herdr-reference-2026-10-14`. No installation, daemon or actual user pane was accessed.

- `src/api/schema/panes.rs`: stable workspace-qualified pane IDs, current/foreground cwd, labels, agent identity and reported status.
- `src/api/schema/common.rs`: states idle, working, blocked, done and unknown.
- `src/cli/pane.rs`, `src/cli/agent.rs`, `src/api/client.rs`: CLI wrappers for the local socket protocol. This separates real pane state from a UI's assumptions about a running process.
- Herdr owns PTYs and its background server. The user asked for analogous multi-session workspace behavior inside Sieg, not a connection to Herdr. No Herdr runtime or CLI invocation remains in Sieg.

This slice provides one shared room for each selected conversation, with nested workers reported by Codex and Claude's supported runtime events. A PTY emulator, worker creation/splitting, dependency scheduling and remote SSH are future work.

[Repository](https://github.com/herdrdev/herdr) · [CLI source](https://github.com/herdrdev/herdr/blob/6521382dbed36f2d001417108149c338aee116ea/src/cli/agent.rs) · [Pane schema](https://github.com/herdrdev/herdr/blob/6521382dbed36f2d001417108149c338aee116ea/src/api/schema/panes.rs)

## Clicky screenshots: observed experience and remaining proposals

The user's screenshots show small agent portraits/status dots near the screen edge, brief activity cards, a larger conversation/history view, artifact previews and suggested next steps. They also show onboarding with spoken/typed input and a hold/release voice gesture. They do not establish private implementation details.

The current slice uses a visual workroom → selected compact chat, retaining drafts and actual provider states. The earlier compact activity/popover proposal was superseded by the user's Coucou/workroom correction. A persistent screen-edge dock, sidebar history with artifact cards, contextual suggestions and a guided hold-to-talk onboarding are recorded for the next design/voice slice. Reuse Sieg characters, interactions and colors; do not copy Clicky's art or marketing wording.

[Clicky](https://www.heyclicky.com/) · [Coucou chat study](coucou-chat-2026-10-13.md) · [Official Codex App Server history](https://learn.chatgpt.com/docs/app-server)
