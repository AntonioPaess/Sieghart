# Clicky reference — voice with context

October 11, 2026. Requested by the user. Public product research; no Clicky binary was downloaded, inspected or run. These are product proposals, not delivered Sieghart capabilities.

## Verified public description

- [Clicky's FAQ](https://www.heyclicky.com/) describes an on-demand hotkey, spoken questions about the visible screen, guidance drawn over the screen, and a distinction between conversation and executing agent tasks.
- Its [trust page](https://www.heyclicky.com/trust) says screen access happens on hotkey activation, raw screenshots are not stored, generated screenshot analysis and prompts are retained, and processing is forwarded to Anthropic or OpenAI in the cloud. It also describes an optional daily read of connected integrations for morning suggestions.
- The linked [GitHub repository](https://github.com/farzaa/clicky-releases) distributes appcast data and binaries. This is not evidence of a published application source tree. The site's claims do not establish its endpointing algorithm, audio transport, model prompts or latency.
- At the time of this initial product research, the available Burp-project parser covered retained HTTP traffic rather than native application inspection. REA was subsequently installed; the static investigation below supersedes this setup limitation.

## Applying the experience to Sieg

1. One explicit activation opens the existing Companion, shows listening immediately and provides live transcription. End the utterance when speech stops; permit cancel/interruption. Validate AirPods and built-in input independently.
2. The user can attach selected text, a file or on-demand screen context. Show the attached context before execution. Text extraction can use appropriate Accessibility/Vision adapters; Foundation Models is not itself a screen-capture or speech engine.
3. Interpret the request as help, dictation or action. Asking for an explanation and requesting an operation have distinct outcomes in the same Companion surface.
4. Present one useful next action. For a verified UI target, a restrained arrow or highlight can explain the instruction. Moving windows and ambiguous targets need handling before promising arbitrary-app guidance.
5. Persist the requested outcome, completed stages and next step locally. A later retry/resume must preserve prior completed actions and reject stale results.
6. Execute through existing native services and supported connected adapters. The UI's listening/thinking/working/success states follow actual events. Provide typing and keyboard equivalents.

## Optional deeper study

With an available copy of the app, a separate isolated investigation could record observable states, interruption behavior, audio-device changes and response timing; inspect bundle metadata, frameworks, entitlements and published distribution assets; and distinguish observations from architectural hypotheses. Runtime speech, screen access, external traffic and account actions need their own authorized test conditions. Public documentation is sufficient for the current experience proposal; no claim of reconstructing Clicky's private implementation is made.

The current instruction to keep Sieghart closed and leave real hardware tests to the user remains in force.

## Subsequent static study

The user selected HeyClicky and HeyTaby for investigation. The [first static study](Research/hey-assistants-2026-10-11/README.md) records official package identities, REA evidence, selected shipped implementation observations, integration boundaries and remaining unknowns. HeyClicky 1.0.53 and Taby 1.0.13 were downloaded and inspected without installing or launching either app. This does not establish runtime performance or native Clicky endpointing behavior.
