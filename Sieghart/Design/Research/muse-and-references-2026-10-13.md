# Muse Gadgets and focused references for Sieg

October 13, 2026. Public documentation and selected open source code study. This extends the [Clicky/Taby study](hey-assistants-2026-10-11/README.md) and [OpenJarvis reference](openjarvis-reference-2026-10-11.md). It proposes product and architecture candidates; it does not establish delivered Sieg features.

## Identity and method

The ESP32 clue identifies **Meta's Muse Gadgets**, specifically [facebookincubator/muse-gadget-sdk](https://github.com/facebookincubator/muse-gadget-sdk), which contains ESP32 firmware and a Linux device client. The [official gadget site](https://gadgets.muse.ai/) links this repository. This is separate from the Muse EEG headband and similarly named speech/audio projects.

Source reviewed at commit [`4268880f4bf3e9c736c08ea5efeac6f628fe6f97`](https://github.com/facebookincubator/muse-gadget-sdk/tree/4268880f4bf3e9c736c08ea5efeac6f628fe6f97). The repository is **Apache 2.0**, with separately licensed dependencies, CC0 minimp3, and a BSD font. Its license explicitly excludes the Jollybot avatar. The source license and access to the hosted Muse service are distinct: the documented pairing flow needs the Muse phone app, Developer mode, an SDK token and the [Gadget SDK Terms](https://gadgets.muse.ai/sdk-terms). [Root README and license](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/README.md).

The REA skill routes ordinary complete source analysis to normal repository tools. Accordingly, this part used official docs and GitHub source reads, without REA readiness, decompilation or claims about observed application execution. No application, firmware, installer, microphone, model, account integration or device was started. Production source was not edited.

## Muse: local device, remote assistant

| Component | Evidence and boundary |
| --- | --- |
| Device hardware and presentation | The firmware handles buttons, microphone capture, LEDs/screens, captions, speaker/MP3 infrastructure, volume and sleep. Available features depend on the board. These are local peripheral operations, not local model inference. |
| Provisioning | BLE pairs the device through the phone app; the device joins Wi-Fi and obtains device/VM credentials. Community pairing is documented without manufacturer verification. |
| Agent connection | Both SDKs connect to the user's Muse VM through a WebSocket upgrade at `/v1/noise`, then an encrypted Noise session. Hosting the gadget at home does not host the Muse agent at home. |
| Voice recognition | The active ESP32 source sets `VOICE_NOTE=1`: it streams a WAV voice note to `/chat/stream`, and the server transcribes it. A dictation path exists, but its source comment says that endpoint currently has no ASR. It is not evidence of working local or streaming ASR. |
| Replies and speech | Default ESP32 replies are text. `start_tts` currently creates silence to pace captions; the source documents where a chosen TTS API could be added. The Linux client already exposes an optional voice reply plus remote TTS stream. Neither path demonstrates local TTS generation. |
| Home-network tunnel | The remote agent can reach local HTTP devices through the gadget on supported boards. Boards without sufficient PSRAM omit that tunnel. A local destination reached through a cloud agent is still a remote dependency. |
| Linux actions | Muse can invoke shell commands and read/write files as the configured Linux account. The SDK is an execution endpoint, not a complete local desktop assistant. |

Sources: [ESP32 README](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/esp32/README.md), [active ESP32 voice path](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/esp32/components/muse/muse_chat_session.cpp#L119), [caption/TTS implementation](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/esp32/components/muse/muse_chat_session.cpp#L1504), [Linux voice/TTS implementation](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/linux/src/musegadget/link_client.py#L272), [Linux command contract](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/linux/README.md).

The inspected repository supplies device clients and firmware. It does not establish that the complete phone app, hosted VM agent, model service or a compatible self-hosted backend is open source. Replacing a host address alone would not provide the pairing, authentication, chat and command services the client expects; that is an inference from the inspected contracts.

### Patterns worth adapting

- **A bounded device contract.** `/link-control` carries length-prefixed JSON: a device advertises commands with `link.register`, receives `link.invoke`, and returns `link.result`. A Sieg satellite could advertise only its supported inputs and outputs. Keep Sig's reasoning and task ownership on the Mac. [Protocol implementation](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/linux/src/musegadget/link_client.py#L17).
- **Cancellation tied to request identity.** The ESP32 session tags turns with a generation so events/audio from a cancelled turn are dropped. The Linux turn tracker also binds replies to acknowledged requests and handles older events. This maps to Sieg's listening, working and result states, including avoiding a late celebration after Cancel. [ESP32 session](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/esp32/components/muse/muse_chat_session.cpp#L34), [Linux turn tracker](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/linux/src/musegadget/muse_turn.py).
- **Separate acknowledgement from completion.** A chat acknowledgement identifies the posted user message; the response follows on `/chat/subscribe`. Current ESP32 turns settle after completed messages and a quiet interval. Sieg should expose an explicit local task result for file handoff, rather than treating transport acknowledgement or a quiet stream as completion. [Turn completion logic](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/esp32/components/muse/muse_chat_session.cpp#L1650).
- **Complete file writes before replacement.** Linux file transfer accepts ordered chunks up to 64 KiB, stages a private partial file and atomically replaces the target when the last chunk arrives. SHA-256 verification is optional in this implementation. This is useful for future artifact delivery; Sieg should require verification when bytes cross a transport. [File implementation](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/linux/src/musegadget/fileops.py), [command schema](https://github.com/facebookincubator/muse-gadget-sdk/blob/4268880f4bf3e9c736c08ea5efeac6f628fe6f97/linux/src/musegadget/executor.py#L68).

For a future **fully local ESP32 satellite**, a useful comparison is Home Assistant's [documented local Assist pipeline](https://www.home-assistant.io/voice_control/voice_remote_local_assistant/): local Speech-to-Phrase or Whisper, plus Piper. The microphone device and the inference host are distinct. Speech-to-Phrase supports a bounded home-command vocabulary; an open-ended Sieg task needs another recognition path. This establishes an architecture reference, not compatibility with Sieg or a tested board choice.

## Four focused application references

These are interaction and implementation references. No clinical effectiveness for ADHD is claimed; the proposed flows aim to reduce setup steps, lost context and decisions before starting a task.

### 1. DropPoint — file handoff

[GameGodS3/DropPoint](https://github.com/GameGodS3/DropPoint), [GPL 3.0](https://github.com/GameGodS3/DropPoint/blob/137789de41104f969ee5c521558c8ee366156a82/LICENSE), reviewed at `137789de41104f969ee5c521558c8ee366156a82`.

Its documented flow is to collect files/folders in a small floating place, switch to the destination and drag them out. Source stores file paths, then calls Electron's native `startDrag`. It clears the visual list at drag start and requests closure; the inspected path does not confirm destination acceptance. [Renderer](https://github.com/GameGodS3/DropPoint/blob/137789de41104f969ee5c521558c8ee366156a82/renderer/droppoint.js), [native drag handoff](https://github.com/GameGodS3/DropPoint/blob/137789de41104f969ee5c521558c8ee366156a82/src/RequestHandlers.js).

**Sieg candidate:** Toni holds a compact file card while the user changes apps. Show name, thumbnail, count and destination. Keep the card available after a cancelled/failed drag; let the user retry or clear it. Distinguish holding a reference to a file from copying, moving or sending its bytes. Copy the interaction idea through a native implementation; importing GPL application source is a separate decision.

### 2. VoiceInk — native local dictation and delivery

[Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk), [GPL 3.0](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/LICENSE), reviewed at `5628765e92f7630ecdeb9a09f798fbd80b76b243`.

The native Swift app provides shortcuts, app-specific modes, transcription and output delivery. Its service registry selects local Whisper/FluidAudio/transcribe.cpp/native Apple routes or a cloud route by provider. Therefore the README's general offline claim should not be applied to every selected configuration. [Service registry](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Workflows/TranscriptionServiceRegistry.swift).

`CursorPaster` distinguishes whether the paste command was posted and restores the old clipboard only while its text and session marker still own the clipboard. That return value is not proof the destination inserted the text. A separate delivery layer handles paste, response and custom-command modes. [CursorPaster](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift), [delivery](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/Features/Recording/Workflows/TranscriptionDelivery.swift).

**Sieg candidate:** explicit dictate/help/action intent; a visible transcript and chosen destination; provider selection that clearly identifies local execution. Preserve clipboard ownership and cancellation. A small local model can be prepared when appropriate; VoiceInk's optional prewarm is a lifecycle reference, not evidence that persistent model residency improves Sieg's energy or latency. [Prewarm source](https://github.com/Beingpax/VoiceInk/blob/5628765e92f7630ecdeb9a09f798fbd80b76b243/VoiceInk/App/Lifecycle/ModelPrewarmService.swift).

### 3. Hammerspoon — precise macOS actions

[Hammerspoon/hammerspoon](https://github.com/Hammerspoon/hammerspoon), [MIT](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/LICENSE), repository identity pinned at `23e387e2805a9890066366e0ac96c71b27f0cfd5`. This selection reviewed the official API docs rather than a running Lua configuration.

The APIs include global shortcut conflict checks, application identity/activation, choosers, and macOS sharing services. Sharing can test whether a service accepts an item and reports `willShare`, `didShare` or `didFail`; local files are represented as file URLs. [Hotkeys](https://www.hammerspoon.org/docs/hs.hotkey.html), [application API](https://www.hammerspoon.org/docs/hs.application.html), [sharing contract](https://www.hammerspoon.org/docs/hs.sharing.html).

**Sieg candidate:** a small catalog of native actions with explicit targets and result callbacks. Use the native share sheet when an app offers a suitable service; show preparation, dispatch and result separately. Availability and completion differ between services, so an API call alone cannot establish an email recipient received a file.

### 4. Super Productivity — capture, prepare, begin, resume

[super-productivity/super-productivity](https://github.com/super-productivity/super-productivity), [MIT](https://github.com/super-productivity/super-productivity/blob/4bfd15edcd14791c3c1cec9d8e925c48faf013c1/LICENSE), reviewed at `4bfd15edcd14791c3c1cec9d8e925c48faf013c1`. This selection reviewed repository documentation, not runtime behavior.

Its short task syntax captures title, time estimate, tags/project and dates in one input, with detected fields highlighted. Focus mode separates selecting/preparing a task from pressing Start; task tracking and focus can pause/resume together. Its three timer modes have distinct completion policies. [Short syntax](https://github.com/super-productivity/super-productivity/blob/4bfd15edcd14791c3c1cec9d8e925c48faf013c1/docs/wiki/3.04-Short-Syntax.md), [focus lifecycle](https://github.com/super-productivity/super-productivity/blob/4bfd15edcd14791c3c1cec9d8e925c48faf013c1/docs/wiki/4.15-Timers-and-Focus-Mode.md).

**Sieg candidate:** a spoken intention becomes one editable next action with an optional short duration. “Prepare” brings up the file/app and necessary context; “Start” activates the task and focus session together. “Pause” saves the continuation point. A timebox ending and a task being completed remain separate events. Sieg does not need to inherit the reference app's full dashboard or scoring system.

## Recommended order and acceptance evidence

| Priority | Candidate | Evidence required before promising it |
| --- | --- | --- |
| 1 | Toni file card and destination handoff | Real drag/share cancellation, unavailable/moved source files, duplicate filenames, multiple files and recovery. Success comes from the relevant destination contract. |
| 1 | Reliable local voice, transcript and delivery | Selected offline provider with assets ready, Portuguese recognition, device changes, cancellation and no stale action. Separate time to final transcript from time to delivered result. |
| 2 | Sig turns an intention into one next action; Gantt offers a short focus block | Start/pause/resume preserves task/file context; preparation has no execution side effect; timer completion does not mark unfinished work done. |
| 2 | Bounded native action adapters and real task status | Target identity, capability checks, typed results and retry without duplicate delivery. Review native callbacks before adding broad computer use. |
| 3 | Optional ESP32 desk satellite | First prove an authenticated local Mac transport, disconnect/reconnect, cancellation, muted/offline behavior and full local voice routing. Board, battery and renderer selection follow those contracts. |

Muse is most useful now as a **device contract and request-state reference**. The file shelf and local voice delivery offer more direct gains for Sieg's current Mac experience. A Muse-connected gadget would add a hosted-service dependency to the mandatory offline demonstration; a Sieg satellite would need its own local transport and inference pipeline.

## Remaining uncertainties

- No device, application or reference configuration was exercised, and no CPU/GPU, memory, power or latency comparison was measured.
- Source and documentation differ around TTS: the default ESP32 implementation is text/caption based; the current Linux API exposes optional remote speech. Service-side availability remains untested.
- Muse's underlying model, hosted agent implementation, service retention policy and complete permission behavior are outside the inspected device-source scope.
- The short selected code paths do not establish whole-app security, accessibility, resilience or Portuguese accuracy for any reference.
- Dependency/model/asset licenses remain separate from each application's root license. No reference code or proprietary character art was incorporated into Sieg.
