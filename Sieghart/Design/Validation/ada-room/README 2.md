# Ada room validation — October 13, 2026

## Verified locally

- Signed Debug build: `/private/tmp/sieghart-s5-final/Build/Products/Debug/Sieghart.app`, 104 registered Swift sources. Build log: `/private/tmp/sieg-room-build-v3.log` (`BUILD SUCCEEDED`).
- Built-bundle privacy purposes, menu-bar-agent metadata and code signature: `Tests/verify-built-app.sh` passes. App not launched.
- `SIEGHART_CHECK_FILTER='^agent-room$' bash Sieghart/Tests/run-checks.sh`: passes. Log `/private/tmp/sieg-room-checks-v3.log`.
- Existing `interactions` group also passed after the initial room routing integration. Log `/private/tmp/sieg-room-checks-final.log`. Later changes concerned chat adapters and the room's display/preview; no wider test expansion was needed.
- `bash Sieghart/Tests/render-agent-room.sh`: five offscreen 2× exports. Log `/private/tmp/sieg-room-layout-v3.log`. Disconnected, working, waiting and completed widget, plus completed full-room layout inspected. Native menu/input/scroll containers have static equivalents for ImageRenderer; those exports do not establish actual keyboard focus or native scrolling behavior.
- Codex's locally installed CLI exported its JSON schema without connecting or doing inference, at `/private/tmp/sieg-room-schema-final`. Approval/sandbox enums and response envelopes were checked against it. Official Claude Agent SDK docs confirmed local session APIs, streamed user envelopes/UUIDs and query/resume options.

## Isolated checks cover

No automatic connection on construction; per-session draft preservation; switching sessions during a pending history read; live delta/final-message coalescing and order; completion only on provider result; send rejection without overwriting newly typed text; stale/missing question rejection; disconnected loading/approval cleanup; room visibility on pointer departure; runtime timeout/cancellation/EOF; fast Codex completion before send receipt; idle events after terminal completion; scoped approval resolution; unsupported server-request rejection; Claude key requirement; new/resumed query identity; history identity matching live messages; multi-part assistant history; actual question-answer envelopes; SDK interruption and stream-without-result failure.

The Codex child and Claude SDK package are authored fixtures in owned temporary directories. The Node bridge is the production bridge executed against that fixture package. None of these checks reads the user's chats, launches a real coding provider, sends network inference, installs hooks, activates mic/audio/clipboard or changes login settings.

## User acceptance remains

Use [manual guide](../../ada-room-test-guide.md). Real provider authentication/session compatibility, keyboard/scroll interaction, cloud inference and CPU during actual provider work are pending the user's run. The first room represents attached provider conversations; nested subagent desks and cross-worker orchestration remain future work. Test conversation names and replies in these PNGs are fixtures, not completed work on the user's code.
