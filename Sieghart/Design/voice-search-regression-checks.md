# Voice, Google search and AirPods — regression checks

October 8, 2026, evening follow-up. The user reproduced a complete transcript staying in **Listening** after speech stopped. This reopens SG-006 acceptance. Implementation is corrected and automated checks pass; **physical speech/AirPods acceptance is pending**. Sieghart and Xcode remain closed during development.

## What failed and what changed

- The previous PCM noise floor only learned samples already below its threshold. A raised headset/room floor could therefore remain classified as speech forever. Initial background calibration and a falling speech envelope now allow audible trailing noise to count as quiet. Changed transcription also preserves recent speech; a short breath/pause does not complete the command.
- Stopping the request called `endAudio` but did not call the recognition task's `finish()`. The native adapter now closes input, ends request audio and explicitly finishes the task to drain accepted audio. **Only a final transcription executes**, once; trailing words are retained. An authoritative `isFinal` received while listening also ends capture immediately.
- Preparation, listening and final recognition now keep **expanded Companion visible with the transcript and Cancel**, even when the pointer leaves or the normal approach timer expires. This supersedes the earlier compact-while-listening behavior. Explicit Cancel/Close still stops voice; normal pointer collapse returns after voice finishes.
- Native engine/request/task ownership is in `Core/Services/Voice/VoiceCapture.swift`, behind `VoiceCapturing`. Activation handles session/UI/actions and accepts a capture adapter and clock. Integration checks drive this production controller path without permission requests, real microphone capture or browser/app launches.
- A fresh engine validates current microphone input/capture formats for each command. Initial headset negotiation can retry once before speech; an input change after speech cancels instead of stitching an incomplete command. Cancellation generations reject callbacks from old/replaced capture.
- Search continues to open **Google in the default browser**, using the existing Portuguese/English search/question parser. Exact query wording, accents and literal plus signs are preserved. Invalid queries do not fall through into timer/app actions.

The endpoint waits for approximately **1.4 seconds of audio quiet**; it is not a fixed sentence duration. Initial silence, loss of audio, a missing final result and the 55-second session safety limit cancel with feedback and execute no partial text. Broadband audio activity is still a heuristic: actual microphone gain, background sounds and recognizer/language availability need physical verification.

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

## Animation status

This correction changes voice completion and visibility, not character choreography. Earlier native animation includes blink/gaze, breathing/sleep, touch reactions and center/drop/wave/dock greeting. Distinct expressive listening/thinking/speaking actions and the user's proposed character gestures remain roadmap work; they are not claimed delivered here.
