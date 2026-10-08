# Voice, Google search and AirPods — regression checks

October 8, 2026. New reports during Sprint 4. Implementation and isolated verification are delivered; **physical speech/AirPods acceptance is pending**. The app was kept closed during development.

## Changes

- Automatic pointer/approach collapse keeps an explicitly started voice session alive in the compact island, with a microphone/status indicator. Clicking reopens Companion; explicit Cancel/Close still stops voice. Recognition/result updates do not reopen a panel the user collapsed.
- Removed the unconditional ten-second capture cutoff and the timer that depended only on changed transcription text.
- Capture now follows PCM activity and approximately 1.4 seconds of quiet, with an adaptive quiet-room floor. A short breath/thinking pause does not end capture; continued speech keeps it running even if recognition text stalls.
- End capture calls `endAudio` and waits for the final transcription, including trailing words. Only a final result dispatches, once. Cancel, input loss, recognition interruption, a missing final result or the 55-second session safety limit do not execute a partial command. Initial silence has its own timeout.
- Cancel voice remains available during permission preparation, capture, headset preparation and finalization. Generation checks discard callbacks from a cancelled/replaced input.
- A fresh audio engine is created for each command and validates current input/output PCM formats. Initial headset format negotiation can retry once before detected speech; an input change after speech cancels instead of stitching an incomplete command. Planar/interleaved Float32 and integer PCM are measured with the actual stride, without moving audio buffers onto the UI actor.
- Search opens **Google in the default browser**. Portuguese “pesquisa”, “procura”, “busca”, their formal variants, “faça uma pesquisa”, “quero que você pesquise…” and English “look up”/“can you search…” are recognized. General who/what/how/where questions also search; local AI-limit questions retain their existing panel action.
- Queries preserve accents, symbols and topic wording. Control characters/oversized queries are rejected without falling through into timer/app actions. This is a browser search action, not a newly implemented answer-reading agent.

Apple documents that hardware channel/rate changes can stop and uninitialize the engine in [AVAudioEngineConfigurationChange](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange). [inputNode](https://developer.apple.com/documentation/avfaudio/avaudioengine/inputnode) documents hardware-format validation; [endAudio](https://developer.apple.com/documentation/speech/sfspeechaudiobufferrecognitionrequest/endaudio()) marks the request complete so recognition can finish.

## Mac acceptance — user performs these checks

1. **Long speech:** activate voice and say a search longer than ten seconds. Keep speaking; the widget must keep listening. Stop, then verify Google contains the last words. Stay below the disclosed 55-second safety limit. Keep the pointer outside the panel as well: the expanded UI should collapse, but the compact microphone indicator and capture should continue.
2. **Pause:** pause for about half a second in the middle of the sentence, then continue. Only the quiet period at the end should finish it. Check a quieter voice in a quiet room as well.
3. **Cancel/retry:** cancel during listening or “Finishing your command…”, then start a different command. The cancelled command must never open an app/browser. Stay silent once: no command should run.
4. **Search:** select the voice language you will speak in Activation, then try “pesquisa no Google sobre animações fluidas”, “procura receitas de pão” and “quem criou o Swift?”. Verify Google, complete wording/accents and no unintended timer action. “What are my AI limits?” must still open the local dashboard.
5. **AirPods:** in Audio → Microphone confirm the input you want (AirPods or the Mac microphone), then invoke voice. Test with AirPods already connected, connect before the next command, and disconnect during speech. A transient preparation may retry once; after spoken input is interrupted, it should report retry and run nothing. Repeat with the Mac microphone. Report the displayed status if capture still fails.
6. **Resident behavior:** repeat a normal command after closing the main window with the red button and in another full-screen app. This verifies that the changed voice lifecycle retains the accepted global-shortcut behavior.
7. **Folder refactor:** verify main/menu/island navigation, avatar choice, persisted preferences, AI dashboard, timers, audio and clipboard still behave as before. No preference reset is needed.

Room noise, muted inputs, Bluetooth negotiation and recognizer/language availability still require physical verification. The activity detector is a level-based endpoint heuristic, not a semantic detector of user intent or a promise to distinguish speech from every background sound. No live microphone, app window, clipboard, global shortcut or audio-device change was used in the automated checks.

## Automated evidence

Twelve isolated groups pass after the folder refactor; targeted voice/parser/UI integration checks are repeated after the final voice changes. Voice fixtures cover forty-second continued speech with stalled text, short pauses, quiet voice, initial silence/input loss, final-word drain, exactly-once dispatch, cancellation, bounded negotiation retry and 16/24/48 kHz PCM layouts. Parser fixtures cover natural queries, Google URL round-tripping, negations and invalid-query action isolation. Universal CLI build and package metadata/signature verification cover the reorganized Xcode references.
