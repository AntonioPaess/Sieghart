# Coucou local file receive — source research

Studied October 13, 2026. Public `main` at commit [`71b773f08101237e1ec950efdaee17a626c830e6`](https://github.com/Louis-CFM/coucou/commit/71b773f08101237e1ec950efdaee17a626c830e6), committed October 12, 2026. macOS implementation; source analysis only. No app was launched, no private user file was read, and no artwork or sounds were incorporated into Sieg. Temporary source checkout: `/private/tmp/coucou-source-2026-10-13`.

## Concrete behavior

1. **Invisible still has a notch target.** The transparent AppKit panel remains present at screen top center, sized 720 × 560. `currentIslandFrame` uses hidden notch dimensions, compact notch width +160 with the same height, or expanded view dimensions. A pointer poll switches the panel from click-through to accepting mouse events when inside that island rectangle; on a notched display it adds a 6 pt margin. Ordinary entry peeks hidden → compact, or opens fully if the optional open-on-hover preference is enabled. There is no global file-drag detector in this flow.
2. **File drag entry opens the target.** An AppKit `NSView` sibling of the SwiftUI hosting view registers `.fileURL`, returns `nil` from normal `hitTest`, and implements `NSDraggingDestination`. Entry and update return `.copy`. On entry, the controller sets `fileDragOver`, starts the upload engine **before** switching the view, posts `.hookExpand(.upload)`, then requests the normal bot's morph to 1. The hook observer synchronizes the FSM to home and expands to upload without needing a click. The regular bot is hidden while the dedicated canvas draws the receive sequence. The shell opens with spring response 0.5 s, damping 0.72.
3. **A visible receiver follows the file.** The expanded target is 640 × 176; its inset card is `(10,42,620,124)` with radius 20. A 62 pt receiver starts at `(140,104)`, follows horizontal cursor position clamped to 60…580 and tracks it with eyes and body tilt. The target has marching green dashes, an upward green wash, a drop instruction and file type chips. The canvas draws a document at cursor+(0,14), before the actual drop. The target accepts registered file URLs at AppKit level; its delegate has no additional card-shape hit test or file-type/size validation.
4. **Leaving does not immediately fold it.** Drag exit resets `fileDragOver`, requests bot morph 0, and calls an empty `exitZone`. Both the expanded island and upload engine deliberately remain active. Normal FSM mouse-leave handling can start the configured home collapse timer (default 15 s); it is not an immediate drag-exit collapse.
5. **Drop starts the animation immediately.** The handler processes `urls.first` only. It immediately sets `DroppedFile(original URL,name)`, `promptContext.file`, progress 0 and drag-over false, records a fixed 2.4 s animation duration and enters `.uploading`. It posts gulp/happy feedback and uses Coucou's own approve/tick sounds. A detached task creates `Application Support/NotchBuddy/inbox`, removes an existing item of the same basename and copies the original there. Success swaps both state URLs to the inbox copy. Failure silently retains the original URL. The original is never removed or moved.
6. **Ready offers an explicit next action.** After approximately 1.3 s of receive/shrink and 2.4 s of cosmetic progress, the receiver regrows. The canvas presents a filename-ready state and buttons for a question or email. It moves to `.choose` after a further 1 s wait (4.7 s after drop). Question opens `.prompt`; email opens `.mail`. No model request or email is sent by the drop itself.
7. **The file becomes visible chat context.** Prompt shows a filename capsule above conversation/input. Sending a nonempty query calls the chat service with `promptContext`. Anthropic includes actual file data on the first conversation message: PDF documents; JPEG/PNG/GIF/WebP images; UTF-8 text/code up to 200 KB. Other cloud compatible providers send the filename only; local providers inline nonbinary UTF-8 text up to 24,000 characters. Existing chat history is not reset by file drop, while context addition is limited to an empty model conversation, so a new file dropped into an existing conversation can appear in the UI without being included in the next request.

### Source anchors for reveal and routing

All links pin the audited commit:

- [Panel and native drag wiring — IslandWindowController.swift L76–178](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandWindowController.swift#L76-L178).
- [Poll and click-through switch — L432–484](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandWindowController.swift#L432-L484).
- [External expand observer — L858–862](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandWindowController.swift#L858-L862); [shell transition and expand — L587–610](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandWindowController.swift#L587-L610).
- [Native destination — FileDropView.swift L8–39](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/FileDropView.swift#L8-L39).
- [Hidden/compact/expanded sizes — controller L2027–2039](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandWindowController.swift#L2027-L2039); [FSM entry/leave — IslandStateMachine.swift L60–114](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandStateMachine.swift#L60-L114).

## Receive motion evidence

This table describes source choreography, not permission to copy Mochi's appearance or character animation. Sieg should interpret receiving with its own character artwork and motion.

Times below are relative to the actual drop. The engine uses reference drop time 1.95 and resets that clock on release, preserving the cursor-follow spring's current position and velocity. Long hovers clamp phase-sensitive values to pre-drop so receiving cannot start early.

| Time | Source behavior |
| --- | --- |
| Drag entry → +0.38 s | Round-to-box body morph using back ease, capped at 1.08. Diameter remains 62 pt. |
| Drag hover | X spring response/damping 0.35/0.70, or 0.18/0.75 when locked. Lock when cursor distance to `(bodyX,bodyY−14)` <60 pt and cursor speed <180 pt/s; release >90 pt. Lock has a −5 pt hop over 0.15 s. Tilt target is horizontal body velocity ×0.0015 capped ±0.18 rad. |
| Mouth during hover | Independent aperture spring response/damping 0.25/0.60. Target 0.20 ×radius ajar, 0.42 when locked. At drop target becomes 0.50 until suction ends. |
| 0…0.08 s | Anticipation: X scale 1→1.06; Y 1→0.92 with cubic out. |
| 0.08…0.38 s | Suction: X 1.06→0.97; Y 0.92→1.06 with cubic in/out. Document moves from release cursor toward the top aperture and narrows as it enters; hidden at 0.38 s. |
| 0.38…0.47 s | Mouth closes using cubic in. |
| 0.38…0.65 s | Recoil: Y 1.06→0.82 at 0.45→1.10 at 0.58→1 at 0.65; X 0.97→1.14→0.95→1. |
| 0.65…0.93 s | Chew pulses, 0.14 s period: Y `1−0.05 sin(πk)`, X `1+0.03 sin(πk)`. |
| 0.93…1.28 s | Morph shrinks to a ball, diameter 62→14 pt, position slides to progress start `(46,118)`. Stretch Y `1+0.12 sin(πk)`, X `1−0.06 sin(πk)`. |
| 1.05…1.30 s | Progress track reveals, with overlapping opacity reveal. |
| 1.30…3.70 s | Fixed 2.4 s progress; receiver becomes a 14 pt moving leading-edge dot, x46→520. Curve reaches 60% in first 40% of duration, 92% by 85%, then finishes. Stretch depends on progress velocity, capped at X1.25/Y0.85. This is independent of actual background copy completion. |
| 3.70…3.95 s | Completion check and green flash; −8 pt hop over 0.20 s. |
| 3.95…4.40 s | Regrow with back ease to 62 pt, move to choose position `(60,101)`. Green wash fades subsequently. |
| 4.10…4.40 s | Choice text/buttons fade in and rise 4 pt; hit testing enabled only above opacity 0.5. |
| 4.70 s | Handler marks view `.choose`, maintaining the same canvas until the next user action. |

The aperture is at the **top of the box body**, not a rectangle pasted across the middle of the face. In `drawMochi`, radius is `diameter/2/1.04`, mouth height is `mouth × radius × clampedMorph`, width is `2 × bodyHalfWidth −0.24 ×radius`, and its top is `−bodyHalfHeight +0.10 ×radius`. The drawing is clipped to the body, uses a dark cavity gradient, and adds a bottom lip once height exceeds 4 pt. Suction splits the document into 28 horizontal strips, translates it toward the aperture, narrows bottom strips, adds slight ±0.1 rad wobble, and clips away everything below the mouth midpoint. Four green particles also converge into the aperture. Dashed border travels approximately 20 pt/s with dash lengths 6/5, width 1.5 pt. Hover wash is 0.22; progress wash rises to 0.50 and flashes by an additional 0.20.

### Source anchors for motion

- [Constants/times — UploadSequenceEngine.swift L9–38](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadSequenceEngine.swift#L9-L38).
- [Easing/recoil/progress curve — L45–77](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadSequenceEngine.swift#L45-L77).
- [Entry/drop/exit lifecycle — L177–232](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadSequenceEngine.swift#L177-L232).
- [Follow/lock/mouth spring — L254–290](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadSequenceEngine.swift#L254-L290).
- [Body, position, squeeze, gaze, alphas — L304–418](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadSequenceEngine.swift#L304-L418).
- [Card/border — UploadCanvasView.swift L90–155](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadCanvasView.swift#L90-L155); [mouth aperture — L337–361](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadCanvasView.swift#L337-L361); [suction — L415–471](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadCanvasView.swift#L415-L471).

## Staging, cancellation and cleanup limits

- Background inbox copy and immediate context staging: [FileDropView.swift L45–83](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/FileDropView.swift#L45-L83). The single-file UI retains basename only; same-name inbox items are replaced. Actual copy success does not gate the ready display.
- Wait/tick flow and transition to ready: [L85–122](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/FileDropView.swift#L85-L122). Copy/tick/wait tasks are not stored for cancellation and have no generation guard. Sleep errors are ignored. A late copy can replace newer context; the old handler can switch to choose after navigation away.
- The engine's `exitZone` is empty; `deactivate` only clears active/drop timing ([engine L203–219](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadSequenceEngine.swift#L203-L219)). It does not clear cursor/lock/entered state, context, or inbox files. There is no native drag-ended/cancel callback in the drop view.
- Navigating outside upload/uploading/choose while expanded deactivates the canvas ([IslandRootView.swift L149–155](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandRootView.swift#L149-L155)). Choice buttons change view then schedule another deactivation after 0.22 s ([canvas L50–85](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/UploadCanvasView.swift#L50-L85)). Collapsing changes mode and resigns key without clearing upload engine/file context ([controller L612–635](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandWindowController.swift#L612-L635)).
- Ordinary email cancel returns to choose. Voice-draft email cancel clears its draft and `droppedFile` then collapses ([IslandViewContent.swift L1071–1084](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandViewContent.swift#L1071-L1084)). No inbox-file removal after chat/mail or dismiss was found in this flow.
- Inline filename context: [prompt L1300–1303](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandViewContent.swift#L1300-L1303), [chip L4765–4797](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandViewContent.swift#L4765-L4797), [explicit send L1450–1470](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/IslandViewContent.swift#L1450-L1470), [Anthropic first-message context L260–277](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/ClaudeService.swift#L260-L277), [file read formats L740–760](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/NotchBuddy/Sources/App/ClaudeService.swift#L740-L760).

## Application to Sieg

Match the useful sequence: a native file destination on the collapsed avatar/notch, automatic expanded target on valid drag, pointer-follow attention, visible intake after drop, filename attachment inside Companion chat, and explicit user send. Use Sieg's original character shape and expressions. Preserve the actual original file, avoid displaying fabricated upload progress, and tie ready/error to actual staging. Use one generation/cancellation owner for hover exit, drag cancel, animation, staging and navigation so obsolete callbacks cannot revive a dismissed flow or replace newer context. Chat must include the newly attached context even in an existing conversation.

## License boundary

[`LICENSE`](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/LICENSE) grants MIT rights to source code with its attribution requirement. [`LICENSE-ASSETS.md`](https://github.com/Louis-CFM/coucou/blob/71b773f08101237e1ec950efdaee17a626c830e6/LICENSE-ASSETS.md) separately protects the names, Mochi character design/look/expressions/animations as a character, icons, sounds and media. Behavioral research and source math do not authorize shipping that protected identity or art. Keep Sieg's own name, character, icon, visual receiving interpretation and sounds.
