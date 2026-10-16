# Ada’s Apple 27 agent chat: manual acceptance

Updated October 16, 2026. User-approved direction: **Apple Cloud with thinking for the complete app; new on-device Apple model for offline use.** Codex/Claude chat runtimes remain outside this flow. Optional third-party AI API keys are future work.

## Requirements before a real model test

The development Mac was verified on **macOS 27.0.1** on October 15. Both chat modes require **macOS 27+**, so the observed host now satisfies that OS prerequisite; actual model availability and response quality remain unverified. Compiling with Xcode 27 alone does not upgrade an older host or grant Apple service access. The old macOS 26 model is not used as a fallback.

- **On this Mac:** requires a ready/enabled Apple Intelligence model. Sieg verifies the actual AFM 3 variant (`core3` or `coreAdvanced3`) and displays its name; it cannot force a larger variant onto unsupported hardware. This mode has no official thinking control or cloud-model fallback.
- **Apple Cloud · Thinking:** requires network, Apple Intelligence eligibility and the managed `com.apple.developer.private-cloud-compute` entitlement approved by Apple and present in the app’s signed provisioning. Default reasoning is **Deep**. The shipped development entitlements are not modified to pretend that approval exists. This mode remains unavailable until those requirements are satisfied.

After Apple grants access, enable Private Cloud Compute for the app’s identifier/team and regenerate an authorized provisioning profile in Xcode 27. Then sign the app with that capability and verify it in the final executable. Merely inserting a Boolean in an entitlement file does not grant access. [Apple PCC access](https://developer.apple.com/private-cloud-compute/) · [Managed entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.private-cloud-compute).

## Test the chat

Quit the previous resident process with **⌘Q** and open `/private/tmp/sieghart-s5-ada-apple27/Build/Products/Debug/Sieghart.app`. Automated checks never open Sieg or Xcode.

1. Click **Ada → + New chat**. A Sieg-owned conversation opens directly. No Codex/Claude sign-in, AI API key or project chooser is involved.
2. Open **Ada settings** (sliders icon). Verify model choices, privacy/network description and **Deep** thinking selected for Apple Cloud. On macOS 26.6.2 expect the explicit macOS 27 requirement, with history and draft preserved. On macOS 27 without an approved app entitlement, expect the precise PCC approval message; choose on-device chat to test the available local model.
3. In a supported mode, ask “Who are you and how can you help me debug this Swift function?” and paste a small excerpt. Ada should respond as the resident senior coding companion, using the user’s language, clear steps and concrete engineering advice. Instructions describe her exact connected capabilities, rather than a generic prohibition on outside information.
4. Send using both **Return** and the circular arrow. Expect an immediate user bubble, Ada’s send/working motion and streamed answer. Thinking mode requests `ContextOptions(reasoningLevel: .deep)` from PCC; no private reasoning transcript is fabricated or displayed.
5. Stop a reply. The incomplete turn is discarded and the original question returns to its draft unless new text was typed. Changing model mid-reply is blocked until Stop/completion.
6. Switch conversations during a response. Its answer stays in its original conversation. Only one generation runs at a time. Moving the pointer away keeps chat open until a widget tab change.
7. Restart: completed history reloads from this Mac. Per-chat drafts persist during the app session. Room cards and the plus tile remain compact; page arrows appear after five conversations.

## GitHub — Coucou’s connection and service-tool pattern

1. In **Ada settings → Ada + GitHub**, enter a GitHub personal access token. Use access to only the repositories you want Ada to see, with read permissions for pull requests, commit statuses and Actions; classic-token/private-repository access needs the corresponding GitHub scopes. Connect validates the account and saves the token in **Sieg’s own Keychain**. Neither Coucou’s credentials nor other apps’ tokens are read.
2. Ask “Which PRs need my review?” or “How is my default-branch CI?” The model’s `github_context` tool retrieves real GitHub account data through the same fixed REST/GraphQL pattern as Coucou: owned-repository/star counts, up to 20 open PRs, up to 20 requested reviews and CI for up to 10 recent owned repositories. Star counts are labeled as sampled from at most 100 owned repositories.
3. GitHub results are cached for 60 seconds and fetched on demand. There is no always-running poller. Only bounded read queries are available. The PAT goes only in the GitHub authorization header; it is never included in the language-model prompt, transcript, error output or local JSON history.
4. In Apple Cloud mode, requested GitHub results can be processed by Apple alongside the question/context. In on-device mode, inference stays on this Mac, but fetching live GitHub data still uses internet. Leave GitHub disconnected for the entirely offline Challenge flow.
5. Disconnect and ask another GitHub question: expect a specific connection explanation, not invented data or an automatic reconnection. Opening Ada after a restart restores Sieg’s previously saved connection once. A disconnected account stays disconnected.

This port matches Coucou’s account/status integration. It does **not** grant arbitrary repository-file browsing, terminal execution, code editing, merge/approval/rerun actions, web/news search or AI-spending queries as chat tools. Ada can analyze pasted code and returned service facts. Future tool adapters must supply real access before those capabilities are advertised.

## Performance and verification scope

Ada reuses cached artwork and sparse Core Animation gestures; no SceneKit renderer or SwiftUI display clock is retained in chat. Reply snapshots publish at most around 15 Hz; Markdown is parsed after completion. The model session exists only during an explicit turn, with no idle prewarming. Native context limits are checked with the local model’s tokenizer, or conservative byte/reserve bounds for PCC, preserving whole recent turn pairs.

History uses private atomic local JSON at `~/Library/Application Support/Sieghart/Chat/history.json`: 20 conversations, 60 messages each, 1 MiB total, 8,000 bytes per question, up to six recent complete turns as model context. The complete saved transcript is not always sent to the model.

Automated checks use injected model generators, temporary histories, memory credentials and fake GitHub transports. They cover streaming, chat identity, cancellation/retry/drafts/history, model configuration persistence, the OS/entitlement requirement matrix and the GitHub connection/cache/bounds path. No actual model inference, account authentication, network API request or real Keychain access is performed. Real model quality, generation latency, CPU and UI interaction remain manual acceptance after the requirements above are met.

## Delivery verification — October 15

- Signed Debug build succeeded; packaged privacy descriptions, menu-bar metadata and signature checks passed.
- Isolated chat, Apple model prerequisite and GitHub service checks passed.
- Ten offscreen layouts are saved in `Design/Validation/ada-apple27`, including cloud/local chat, model unavailability, settings and GitHub connection. Preview-only stand-ins replace native controls that ImageRenderer cannot draw; the running app keeps its actual controls.
- All 126 Swift sources in the isolated build snapshot match the workspace sources. Sieg and Xcode were not opened during verification.

October 16 pre-commit: the companions check's obsolete expectation of a Team rail was corrected to the approved migration to Companion, with Sig fixed as principal. The isolated companions group then passed, including 294 identity/motion pairs. This resolves the previously recorded assertion failure; it does not establish physical performance or account/model acceptance. Development workflow and the visual reference index are in `Design/Workflow/`.
