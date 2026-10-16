# HeyClicky and HeyTaby — first static study

October 11, 2026. User-selected references for My Friend Sieg. This is research, not an implementation change or a complete reconstruction of either application.

## Scope and evidence

Reviewed official product documentation and downloaded the public macOS distributions into a temporary analysis directory. REA 6.4.0 inventoried both DMGs using read-only mounts. Selected packaged files were copied and hashed before static inspection. The applications were neither installed nor launched; microphones, screen capture, accounts and integration actions were not activated.

| Question | Result and boundary |
| --- | --- |
| What can each product do? | Official documentation reviewed; advertised behavior has not been independently exercised. |
| What is shipped? | Both package inventories completed; native imports inspected for Clicky. |
| How does voice finish? | Taby's packaged renderer contains adaptive activity detection and two finish policies. Clicky's exact endpointing implementation remains unknown. |
| How do animations work? | Taby's renderer contains Rive and authored video paths; playback has not been observed. Clicky's avatar implementation remains unresolved. |
| How are agent actions connected? | Taby's public MCP/REST contract and Clicky's bundled computer-use documentation reviewed. Live execution and permissions are untested. |
| Are they faster or lighter than Sieg? | Unknown. No runtime latency, CPU, GPU, energy or memory measurements were taken. |

Original REA records are retained as lossless compressed JSON. [evidence-index.json](evidence-index.json) records their IDs, hashes, operations and limitations. `taby-selected-js-provenance.json` binds the selected JavaScript members to the original ASAR; `taby-renderer-observation-ranges.json` identifies inert renderer text anchors and byte positions. Renderer observations below come from ordinary text inspection, not REA semantic analysis of that renderer.

### Package identities

| App | Observed bundle version | Package SHA-256 |
| --- | --- | --- |
| HeyClicky | 1.0.53, build 64 | `a83c69ee8ec486d2cf9e257aaa39b612539f6b5544d52a4ef2caa652284bd31c` |
| Taby | 1.0.13 | `6aad13c73ae7ba117a743ec6ef48eb9883874937fa2fdd1857174cd766c98104` |

The versioned Clicky asset comes from its [official distribution repository](https://github.com/farzaa/clicky-releases/releases/tag/v1.0.53). Taby's [download page](https://www.heytaby.com/downloads) supplied its Apple Silicon DMG URL. Its non-versioned URL can change; the digest above selects the exact studied bytes.

REA reported **15 ASAR integrity contradictions** in Taby's unpacked native libraries. Inspection continued with `record-and-continue`, preserving those entries as observed-untrusted. Post-packaging signing or stripping is a possible explanation, not an established cause. Those libraries were not executed, and the study does not establish their equivalence to declared hashes.

## HeyClicky

### Documented experience

The [official FAQ](https://www.heyclicky.com/) describes explicit hotkey activation, a spoken question about the visible screen, drawn guidance, and a separate action mode for agents. The [changelog](https://www.heyclicky.com/changelog) describes hold-to-talk follow-ups, listening feedback, practical onboarding exercises, task cards, connected accounts and routines.

The [trust page](https://www.heyclicky.com/trust) states that requests are processed in the cloud. It distinguishes discarded raw screenshots from retained generated analysis and prompts, and documents an optional daily read of connected services. These are published policies, not independently verified network observations.

### Packaged observations

- A native macOS executable contains x86_64 and arm64 slices. REA's Mach-O evidence records imports from native audio, speech and screen-access APIs, together with Core Animation classes. Imports establish available references, not which implementation path handles a particular interaction.
- The bundle includes a `cua-driver` helper, a Codex runtime and computer-use documentation. The packaged README identifies upstream `trycua/cua`, describes an Accessibility snapshot before and after an action, and describes background delivery through a curated MCP surface. This documents the shipped design; it does not prove those actions succeeded in a running app.
- The linked public release repository publishes distribution assets and update metadata. It does not provide the application's complete source tree.

### Ideas for Sieg

1. Keep help, dictation and action in the existing Companion surface, with explicit activation and live state feedback.
2. Let the user attach selected text, a file or an on-demand screen context. Keep enough context for a short follow-up without repeating the original request.
3. Verify an action's result before showing success. An intended click, a queued request and a completed task need distinct states.
4. Preserve completed steps and the next step when an operation pauses, fails or asks a question.
5. Teach one useful operation during onboarding instead of explaining every setting before the user can try anything.

## HeyTaby

### Documented experience

The [local AI page](https://www.heytaby.com/local-ai) describes tasks, a day plan, reminders, calendar context and focus controls. The [integration documentation](https://www.heytaby.com/docs) identifies a local Brain using llama.cpp and distinguishes reasoning from Parakeet speech transcription. It documents a loopback MCP/REST server with named, individually revocable connections and bounded task, card, animation and choice operations.

Its documented MCP direction is **inbound**: an external local client calls Taby. The documentation explicitly says its Brain is not yet an outbound MCP client for Gmail or arbitrary user servers. This distinction matters when designing Sieg's future agents.

### Voice: observed static structure

The shipped renderer includes two activity policies: one keeps listening until explicit completion, while another finishes after speech followed by 1.4 seconds of detected silence. The latter also has separate bounds for no initial speech and maximum recording duration.

The detector combines signal energy, an adapting room-noise floor, minimum speech duration, resumption logic and a periodicity measure. Its code exposes pause progress to the interface. Microphone capture contains a preferred device identifier and browser audio processing options. These facts do **not** establish AirPods reliability or real-world endpoint accuracy.

REA parsed ten selected main-process JavaScript modules (45,411 bytes), including voice composition, transcription providers and animation dispatch. Parsing completed without failures for this selection. Whole-app behavior and dependency semantics remain outside that scope; the semantic graph retains partial and unknown relationships.

The selected modules contain separate local/cloud transcription routing, cancellation, provider shutdown and deferred local provider creation. This supports a design with independently managed listening, reasoning and speaking lifecycles; it is not proof that a specific runtime always stays local.

### Animation: observed static structure

- The renderer constructs a Rive instance with an artboard and state machine. It contains bindings for character state, listening, speech motion, expressions and accessories.
- The inventory includes **75 MP4 files** under `assets/animations/notch`. Renderer code maps named states to clips and describes entry-to-loop paths, finite replay and a preloaded handoff layer.
- The handoff code uses `requestVideoFrameCallback` when available, with an animation-frame fallback. This is a concrete frame-readiness technique worth comparing with Sieg's interrupted transitions.
- Animation dispatch rejects requests older than a bounded stale window and can wait for a spoken reply before requesting playback. This is useful for avoiding late celebration or replay after cancellation.

The inspected Rive initialization limits drawing-surface scale to 1.5. That is an observed implementation choice, not a sharpness recommendation for Sieg: our Retina output must be measured at its actual display size. The existence of Rive and MP4 paths also does not establish lower CPU consumption.

### Privacy detail

Taby's [privacy policy](https://www.heytaby.com/privacy), effective October 10, describes local productivity data and optional online features. It also states that an enabled usage-sharing setting can send the first question of a local conversation verbatim. For Sieg, local inference and prompt telemetry should be communicated as separate choices.

## What to improve in Sieg

These are proposals, not delivered features:

| Priority | Proposed outcome | Acceptance evidence |
| --- | --- | --- |
| 1 | Reliable end of speech, visible pause progress, cancellation and clear microphone selection | Deterministic audio fixtures plus built-in microphone/AirPods tests across device changes and background/full-screen use. |
| 2 | One interaction surface for help, dictation and action | A request follows actual listening, thinking, working and result events; cancel prevents a stale result from acting. |
| 3 | A small local plan and a reliable way to resume | A spoken intention becomes a few concrete steps; interrupted work retains completed steps and the next action. |
| 4 | Distinct specialist reactions tied to real events | Sig stays the orchestrator; specialists react to their actual work, with no decorative loading while idle. |
| 5 | Evaluate a different animation renderer without changing the approved greeting first | Compare the same Sieg animation and actual display size using current SceneKit, a Rive prototype and a prerecorded option. Measure whole-app CPU/GPU, energy, memory, sharpness, response to gaze and interrupted transitions. |
| 6 | Named, limited integrations with task identity and revocation | Repeated requests do not duplicate tasks or sends; choices expire correctly and access can be revoked. |

Rive may suit expressive interactive motion. Prerecorded motion may suit a fixed greeting. Either requires a prototype and measurements; neither is a proven performance fix from this study. No proprietary character, media or application source has been integrated into Sieg. Reuse of an identified upstream component needs its own compatibility and licensing review.

## Remaining investigation

- Native Clicky endpointing, streaming, context-selection and avatar rendering implementation: needs a configured native analysis engine for deeper static work. No Hopper/Ghidra/IDA engine was installed for this study.
- Real listening interruption, input switching, window behavior and agent cancellation for both apps: not tested.
- Actual animation dimensions, decoding cost, visibility suspension and whole-app resource usage: not measured.
- Taby's complete dependency graph, Brain tool execution and current online features: outside the selected ten-module analysis.
- Current open-source licensing of either complete application: not established. Public binaries, packaged readable JavaScript and published APIs are not evidence of a complete open-source license.

The instruction to keep Sieghart closed and leave physical acceptance tests to the user remains in force.
