# Companion greeting and rendering checkpoint

October 11, 2026 — branch `sprint-5`. The app was built and tested offscreen; Sieghart was not launched. Physical acceptance remains with the user.

## Greeting and handoff

- One 31-second scene owns the introduction. The full approved 4.6-second fall, wave and warm-to-blue light transition finish before the team emerges. The five specialists form a circular reveal from 4.6 to 7.4 seconds and settle into the actual Companion layout by 10 seconds.
- From 10 to 13 seconds Sig announces that he will introduce the Companions. The dock then acts as a rotating queue: the first member takes the main position, the previous speaker takes a lower curved route to the last slot, and the other four advance one slot. Rita, Ada, Gantt, Elinor and Toni each get three seconds. Sig stays visible throughout, returns to the main position at 28 seconds, and introduces himself as the orchestrator who brings the companions and tools together. All five specialists regain their original slots. At 31 seconds the regular Companion replaces the scene at the same sizes and point coordinates. Introduction copy sits 10 points higher than before; the character/dock positions are unchanged.
- The introduction restores the concept's characteristic headlines, in English by default. **Appearance → Introduction language** explicitly selects Portuguese; the setting is independent of speech recognition and the system locale. This choice covers introduction copy; it does not claim complete app localization.
- Greetings are specific to each identity: Rita breathes and nods with her integrated pulse; Ada makes two rigid pixel hops with responding code brackets; Gantt turns his page; Elinor adjusts her monocle and winks; Toni waves her curved paper hand outward. These same gestures are available in the short-hello rehearsal.
- Tapping the introduction skips it. Reduce Motion presents the settled team immediately. Specialists in the dock are passive; they do not launch unrelated tools.
- The opening now retains the approved concept's single 640×360 coordinate space. Fall, wave, halo diameter, staggered emergence, 112-unit circle, 240-degree spin, overshoot and docking arc use the original curves and proportions. The scene's canvas extends into unused vertical space in the existing widget; the widget window is not enlarged. Docking targets remain the actual Companion positions, followed by the accepted rotating queue.
- October 12: removed the rounded horizontal card and its shader after visual feedback. The opening now draws only the characters, circular halo, falling streaks and landing ring; its timing and docking are unchanged.

## Rendering changes

- Idle portraits, including the large Sig, use cached native artwork. Their subtle breathing is a Core Animation layer transform, without SwiftUI frame updates or a retained SceneKit render loop. Gaze and active reactions still use the procedural SceneKit rig.
- One SceneKit scene renders the whole greeting. Invisible specialists are hidden; static accessory stroke segments are flattened into one mesh. Blinks reuse geometry rather than constructing meshes every frame.
- After each queue movement, settled specialists keep their existing pose without per-frame transform, eye or accessory writes. One waiting member reacts briefly for 0.85 seconds: a sideways glance, restrained impatience, a small pixel hop or an accessory movement. The entire dock does not animate continuously. Initial particles are hidden after the greeting.
- Hover follows the real pointer with the eyes/head. The simulated cursor prop is excluded from that state; it no longer appears over Sig.
- Greeting, speaker and activity halos draw before opaque character geometry and do not read its depth buffer. This removes the light's hard depth-cut edge around antialiased silhouettes. Identical-pose old/new composition previews were rendered with the app's 2× multisampling and inspected on black; `team-runtime/border-before.png` and `border-after.png` retain the comparison. Character textures and body materials were not replaced.
- Native cached portraits have 512px (1×) and 1024px (2×) assets, exported directly from the rigs rather than enlarged from 256px PNGs. The full-resolution source is retained. After the October 11 sharpness follow-up, each idle portrait is downsampled once with high-quality interpolation to its actual backing size and then composited with linear filtering, replacing trilinear mip filtering. A shared cache is bounded to 48 entries / 8 MB; unchanged layout reuses the raster. Window scale and widget transforms are rechecked on layout/configuration. Idle remains composited by Core Animation; the approved SceneKit choreography is preserved. Re-export source assets with `bash Sieghart/Tests/export-companion-artwork.sh`.
- Loading restores the earlier stationary tinted badge and travelling inner contour. A shader sweeps a 29% segment around the prebuilt stroke mesh every two seconds. The body-shaped spinner no longer rotates. Only its progress uniform changes per frame; idle and listening do not display loading.
- Active poses update on the renderer thread. SwiftUI updates introduction text only at stage boundaries. Finite motions stop rendering after their completion, and detached, hidden, minimized or occluded native scenes pause. Dismantling releases the renderer delegate and scene.
- The renderer uses 60 fps, 2× multisampling and no jitter. Idle portraits preserve the existing lighting and depth; this does not introduce Blender assets or replace the approved character designs.

## Measured renderer performance

Native Metal rendering was measured with Metal API Validation enabled, waiting for actual GPU completion. These are CPU measurements of isolated renderer executables, not the whole Sieghart process. Tests ran on the user's Mac; other processes were not stopped.

Previous Debug run, before restoring the full reference-size opening canvas:

| Scenario | Debug CPU | Debug p95 frame time | FPS |
| --- | ---: | ---: | ---: |
| Sig listening, 192 px | 5.8% | 2.87 ms | 60.0 |
| Sig thinking, 192 px | 9.3% | 3.08 ms | 60.0 |
| Elinor dizzy, 448 px | 9.5% | 3.04 ms | 60.0 |
| Toni hello, 448 px | 6.9% | 2.68 ms | 60.0 |
| Three simultaneous scenes | 10.6% | 4.80 ms | 60.0 |
| Complete six-member introduction, 1064 × 334 px | 11.1% | 7.53 ms | 60.0 |

Earlier measurements were lower (3.9% for the previous introduction). A comparison with the unchanged earlier Debug executable in the current Mac conditions also raised its Sig-listening result from 2.5% to 12.1%; the final renderer measured 10.7%. This establishes run-to-run variation; its exact system cause was not measured. The new introduction also keeps the other specialists visible during each presentation, unlike the previous sequence. Do not treat the earlier 3.9% result as a measurement of this final introduction.

Latest Debug run, with the restored opening and corrected halo composition:

| Scenario | Debug CPU | Debug p95 frame time | FPS |
| --- | ---: | ---: | ---: |
| Sig listening, 192 px | 11.1% | 3.44 ms | 60.0 |
| Sig thinking, 192 px | 11.6% | 3.43 ms | 60.0 |
| Elinor dizzy, 448 px | 10.4% | 3.36 ms | 60.0 |
| Toni hello, 448 px | 9.4% | 2.88 ms | 60.0 |
| Three simultaneous scenes | 24.7% | 7.19 ms | 60.0 |
| Complete six-member introduction, 1064 × 600 px | 11.1% | 4.75 ms | 60.0 |

The latest introduction run rendered all 1,860 frames. The checks verify renderer callbacks stay off the main thread and p95 remains below the 16.7 ms budget. The benchmark uses its own single-sample Metal render target; it excludes native SCNView/window composition and the app's 2× multisampling. Build, preview export and video encoding finished before the latest run; other user processes were not stopped. These figures are not a controlled before/after comparison. Whole-app CPU, hardware voice capture and real UI interruptions still require comparison in the new build.

Reproduce the current Debug GPU checks with `bash Sieghart/Tests/run-companion-render-checks.sh` from the repository root. This renders offscreen and does not launch the resident app or platform services.

## Verification

- Final Xcode Debug build succeeded. The copied app passed signature, built privacy descriptions and Calendar capability verification.
- All 15 groups in `Tests/run-checks.sh` passed across the main run and the four remaining groups. The initial Clipboard fixture hit a macOS temporary-folder access error; the runner now places isolated fixtures under `/private/tmp`. Production Clipboard permissions were preserved.
- After the user's order/loading correction, voice integration, interactions, companions and activity passed again. The final companions check additionally verifies that settled miniatures do not perform repeated pose updates.
- The companion group covers 294 character/motion pairs, cancelled loading, live sleep and bilateral gaze without an extra cursor, interruption continuity, persistent blink meshes, six visible queue members, exact queue slots/final docking, unique and bounded waiting reactions, English defaults/Portuguese persistence, Retina bitmap selection, reduced motion and detached renderer behavior.
- The compiled asset-catalog check confirmed that all six characters yield 1024×1024 CGImages. The first catalog check found that an unspecified drawing context selected the smaller 1× version; requesting an explicit pixel rectangle with an identity CTM fixed the selection. Interaction integration passed again after the new preferences and queue sequence.
- The display-quality follow-up verifies that the original source still yields 1024 pixels, a 38-point idle portrait produces a 76-pixel Retina raster, repeated layout reuses the same raster, and detached portraits remain paused. `Design/Validation/team-runtime/display-quality.png` shows production-cache portraits at 96 and 38 points. Compilation and isolated checks succeeded; perceived sharpness on the user's live display still needs their assessment.
- The final companion checks verify that the opening keeps the source halo diameter, all six active characters draw their light underneath their silhouette, and docking still reaches the real home coordinates. Obsolete expanding-card assertions were removed with that geometry on October 12.
- Native render previews were inspected on a black background. `Design/Validation/team-runtime/hello-companions.mp4` is the updated 31-second, 1064×600, 60-fps offscreen preview of the production choreography. Its captions are rendered from the same SwiftUI component as the app, once per stage, to match the higher text placement and separate welcome/final Sig introduction. The taller render canvas preserves the original opening proportions; it does not enlarge the live widget window. This is not a screen recording of the running app.

## User test

Build: `/private/tmp/sieghart-team-build/Build/Products/Debug/Sieghart.app`. Quit the older Sieghart process before opening this build, or run the updated source in Xcode. The build at this path passes signature verification; the workspace copy acquired Finder metadata, so use the verified build path.

1. Choose **Review introduction**: Sig completes the fall/wave/light sequence, five specialists emerge in a circle, and everyone settles. Sig announces the Companions, the five rotate through the speaking position, and Sig introduces himself as the orchestrator on returning. Sig must stay visible and the final order must be Sig above Rita, Ada, Gantt, Elinor and Toni. Check the higher text alignment, duplicates/jumps and tap to skip.
2. In Activity Monitor observe **Sieghart** CPU and memory for about 30 seconds per state: normal Companion with the pointer away, pointer following, listening/thinking, introduction, then widget closed and workspace minimized. Record the range after each state settles, plus short peaks separately.
3. Repeatedly trigger a reaction, interrupt it with voice/cancel, and close/reopen the widget. Confirm there is no stale loading marker, frozen listening state or continued high rendering cost when hidden.
4. Repeat with **Reduce Motion** enabled: the team should appear settled without the introduction movement.
5. Compare the app's large portrait/motion preview with the widget's small dock at native screen scale. Hover Sig in both directions: his eyes/head should follow without drawing a second cursor. In **Appearance → Introduction language**, verify that the default is English and Portuguese applies only after choosing it.

Do not equate the renderer percentages above with the full application's CPU. A new whole-process capture will establish the improvement in the user's original workflow.
