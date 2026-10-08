# Voice, Google search and AirPods — regression checks

October 8, 2026, evening follow-up. The user reproduced a complete transcript staying in **Listening** after speech stopped. This reopens SG-006 acceptance. Implementation is corrected and automated checks pass; **physical speech/AirPods acceptance is pending**. Sieghart and Xcode remain closed during development.

## What failed and what changed

- The previous PCM noise floor only learned samples already below its threshold. A raised headset/room floor could therefore remain classified as speech forever. Initial background calibration and a falling speech envelope now allow audible trailing noise to count as quiet. Changed transcription also preserves recent speech; a short breath/pause does not complete the command.
- Stopping the request called `endAudio` but did not call the recognition task's `finish()`. The native adapter now closes input, ends request audio and explicitly finishes the task to drain accepted audio. Final transcription dispatches once and retains trailing words. The later topic-search follow-up below adds a bounded settled-search recovery when a final callback is missing; app/timer commands continue to require final recognition. An authoritative `isFinal` received while listening also ends capture immediately.
- Preparation, listening and final recognition now keep **expanded Companion visible with the transcript and Cancel**, even when the pointer leaves or the normal approach timer expires. This supersedes the earlier compact-while-listening behavior. Explicit Cancel/Close still stops voice; normal pointer collapse returns after voice finishes.
- Native engine/request/task ownership is in `Core/Services/Voice/VoiceCapture.swift`, behind `VoiceCapturing`. Activation handles session/UI/actions and accepts a capture adapter and clock. Integration checks drive this production controller path without permission requests, real microphone capture or browser/app launches.
- A fresh engine validates current microphone input/capture formats for each command. Initial headset negotiation can retry once before speech; an input change after speech cancels instead of stitching an incomplete command. Cancellation generations reject callbacks from old/replaced capture.
- Search continues to open **Google in the default browser**, using the existing Portuguese/English search/question parser. Exact query wording, accents and literal plus signs are preserved. Invalid queries do not fall through into timer/app actions.

The endpoint waits for approximately **1.4 seconds of audio quiet**; it is not a fixed sentence duration. Initial silence, loss of audio and the 55-second session safety limit cancel with feedback. A missing final result cancels app/timer actions; settled browser searches have the bounded recovery described below. Broadband audio activity is still a heuristic: actual microphone gain, background sounds and recognizer/language availability need physical verification.

Apple explicitly documents `task.finish()` for buffer recognition in [finish()](https://developer.apple.com/documentation/speech/sfspeechrecognitiontask/finish%28%29), and the final-result contract in [SFSpeechRecognitionResult](https://developer.apple.com/documentation/speech/sfspeechrecognitionresult). [Configuration changes](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange) can stop/uninitialize an engine; [inputNode](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode) documents validating the hardware format.

## Mac acceptance — user performs these checks

1. **Reported case:** select Portuguese in Activation. Start voice, keep the mouse outside the widget and say “Pesquise por ChatGPT no Google”. Stop speaking. Companion must stay expanded while listening/finishing, then Google must open with the complete query. There must be no endless Listening state. Repeat with ordinary room noise.
2. **Long speech and short pause:** say a search longer than ten seconds, pause for about half a second in its middle and continue. Only the quiet period at the end should finish it. Verify the last words in Google. Repeat with a quieter voice. Stay below the 55-second safety limit.
3. **Cancel/retry:** cancel during Listening, permission preparation or Finishing, then start a different command. Old text must never open an app/browser. Leave one attempt silent: it must report no speech and run nothing. Once a command finishes, pointer departure must collapse the panel normally again.
4. **App/timer commands:** try “Open Safari”, “Start focus for 20 minutes” and “Pause the timer”. Confirm each runs once. “What are my AI limits?” must retain its local dashboard route. Ordinary searches must not start focus.
5. **AirPods:** select the intended input in Audio → Microphone. Repeat check 1 with AirPods already connected, after connecting before the next command, and with the Mac microphone. Disconnect during speech: report retry and run nothing. A transient initial negotiation can retry once. Report the displayed status if capture still fails.
6. **Resident/full-screen:** repeat after closing the main window with the red button and from another full-screen app. Companion and the transcript must remain visible during Listening.

## Automated evidence and its limits

- A new regression fixture **failed on the previous implementation**: speech followed by a continuous −42 dB background floor did not end audio. It passes with the new endpoint.
- Unit checks cover raised noise, immediate final results, drain order (`endAudio` → `task.finish`) exactly once, forty-second speech with stalled text, short pauses, quiet voice, silence/input loss, final-word drain, cancellation/timeouts, bounded input retry and 16/24/48 kHz/interleaved/integer PCM.
- `VoiceIntegrationChecks.swift` drives capture events → actual ActivationController → quiet/finalization → actual command parser → Google URL/app/timer actions with injected launch closures. It covers complete last words, duplicate/stale callbacks, a synchronous final callback during finish, cancellation/replacement, final-result timeout, interrupted input, denied/cancelled permission preparation, and pointer/approach visibility throughout busy voice states.
- Thirteen isolated groups pass. The universal CLI build and package/signature checks verify production source wiring. Integration fixtures simulate framework events: they **do not prove** Apple's live recognizer or AirPods hardware works on this Mac. The physical tests above remain the acceptance gate.

## Topic search and expressive voice follow-up

The user then reported “pesquise por arquiteturas de mac” and “pesquisa github” failing while “procure pão” worked. Both reported phrases were already syntactically accepted; no topic whitelist existed. That alone cannot prove where the physical failure occurred. New integration reproductions test both phrases through capture, finalization, parsing and browser action, including the recognizer stopping without a final callback.

- Search now accepts request variants, natural questions and bare topics such as “GitHub” and “arquiteturas de Mac”. Topic words are never a permitted-subject list. Explicit local action grammar takes priority; words inside ordinary topics cannot start a timer. Negated action requests, invalid queries and unavailable email/upload actions are not silently executed.
- If audio has ended and a browser-search transcript remains stable, a missing-final recognizer callback can recover after a four-second drain (up to six seconds if trailing text changes). Only this settled search uses the recovery. Cancel, input loss, the listening safety limit and unfinished app/timer commands never use it. New trailing words must settle before dispatch; duplicate/stale events cannot repeat the search.
- This is Google browser search, not a connected question-answering model, generated answer or fetched result summary.
- Published execution state now lasts for the actual browser/app action. Companion remains visible until the capture/finalization/action phase finishes. Animated success means the native launch action succeeded, not that remote Google content has been inspected.

### New native gestures

All six keep their existing silhouettes, palettes and depth. Preparing has an expectant lean; Listening extends a small ear with attentive tilt and bilateral gaze; final recognition and pending actions use thought dots and curious movement. Successful action launch triggers one hop, full turn and landing. Failure has a brief puzzled shake. Cancellation and phase interruption blend from the current pose; Reduce Motion/disabled character motion preserve static state cues.

[Animated production preview](Concepts/simple-companions-voice.gif) · [Still board](Concepts/simple-companions-voice.png). These are rendered from the same native character view with deterministic preview time, without opening the app.

Actual spoken responses, lip-sync, file/envelope/calendar props, specialist agents and Megabrain are still planned. The thought gesture represents the real recognition/action lifecycle; it is not an implemented agent reasoning engine.

### Additional user checks

Repeat “pesquise por arquiteturas de mac”, “pesquisa github”, “procure astrofísica e buracos negros”, “GitHub” and “Quanto custa um Mac?”. Keep the mouse outside. Each must open Google once with the intended topic. If it fails, report the full transcript and displayed status; real microphone recognition remains unverified by mocked tests. Inspect ear → processing dots → completed hop/turn with each avatar. Disable character motion or enable Reduce Motion: gestures must become still. Cancel during listening/finishing: no late search or continued spin.
