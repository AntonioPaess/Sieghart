# Ada's room validation — October 14, 2026

## Verified without launching Sieg

- Signed Debug app: `/private/tmp/sieghart-s5-room-gallery/Build/Products/Debug/Sieghart.app`, 112 registered Swift sources. `xcodebuild` log: `/private/tmp/sieg-room-gallery-build.log` (`BUILD SUCCEEDED`). `Tests/verify-built-app.sh` passed for signature, menu-bar metadata and privacy strings.
- Isolated room checks: `SIEGHART_CHECK_FILTER='^agent-room$' bash Sieghart/Tests/run-checks.sh` passed. Log: `/private/tmp/sieg-room-gallery-checks.log`. The final layout adjustment changed card dimensions; the subsequent render/build verifies those changes.
- Nine offscreen native view fixtures: `bash Sieghart/Tests/render-agent-room.sh` passed. Log: `/private/tmp/sieg-room-gallery-layout.log`. PNGs include five small conversation rooms plus **+ New chat**, two active children among five total in the selected chat, working chat, approval, disconnected draft, workspace chat and tools without Team. The complete gallery, activity strip/chat and disconnected state were inspected; both rows and the plus tile fit the widget.
- Codex's installed App Server schema was exported locally and checked for parent/child IDs, collaboration tool calls and state vocabulary. The Claude task bridge was exercised against an owned fake SDK, including nested task events and late completion from an older run. Codex rollout observation was checked with a temporary JSONL fixture, including incremental reads and partial final lines.

## What the isolated checks establish

Clicking Ada routes to small conversation rooms with a plus tile; clicking a room opens its chat. Unrelated chats stay in their own rooms. Five lightweight silhouettes cycle as children appear, with stable colors per runtime ID. Discovery uses the selected parent's persisted spawn tree, including nested children outside the recent conversation page. Explicit completed turn status wins over later content timestamps; long silent in-progress tasks remain active. The strip counts working subagents separately from Ada and continues observing while Chat is open.

External Codex roots queue messages without resuming or taking their writer. The exact active-writer error uses the same safe fallback. A queue receipt replaces the provisional bubble with its client identity; persisted `clientId` avoids duplication. Actual native field-editor text reaches arrow/Return submission; fixed session identity prevents sending another conversation's draft. Failures preserve newer text and trigger error feedback. Chat stays open when the pointer leaves or a timer finishes.

Owned never-shown native panel fixtures verify sparse idle with zero ongoing layer animations between gestures, reactions stopping when inactive, fast-send acknowledgement after boolean updates coalesce and failure feedback taking priority over a stale completed state. These lifecycle checks do not measure real process CPU. Team is absent from widget tools; no Herdr or Orca connector is used.

The automated fixtures use authored sessions, processes and temporary state/history databases. Separate investigation read the requested chat's thread/child metadata to diagnose its missing count. No real message was submitted, writer assumed, inference run, hooks installed, microphone/audio/clipboard activated or app opened.

## User acceptance still needed

Follow [the manual guide](../../ada-room-test-guide.md) with the new signed app. Real account/session compatibility, queue consumption, provider event coverage, native focus/scroll behavior and CPU under actual work still need a user run. The compatibility reader supports the installed Codex state/history schema; later storage versions may need adaptation. This chat's persisted parent projection is old, so the UI labels unavailable parent status **Managed in Codex** and displays only replies that its writer publishes to persistent history. Current child identities/states are available separately. Claude SDK versions without child task events cannot expose their nested roster. The names, tasks and answers in these PNGs are test data, not completed work on the user's code.
