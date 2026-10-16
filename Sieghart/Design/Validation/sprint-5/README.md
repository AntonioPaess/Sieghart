# Sprint 5 layout validation

October 12, 2026. Generated at 2× with the production SwiftUI views and local fixture adapters, without launching Sieghart, requesting permissions, reading the real clipboard or invoking Finder/screen capture.

- `shelf-island.png`: bounded shelf subpage, drop surface and file actions.
- `downloads-island.png` / `downloads-full.png`: actual owned fixture files, partial bytes, one final completion/card and folder controls.
- `helpers-full.png`: move/review entry points, rename, URL cleanup and DMG entry.
- `capture-island.png` / `capture-full.png`: supplied local image, annotation, actual local OCR text, hex and task cards.
- `capture-permission.png`: screen-access recovery with supplied-image alternative.
- `files-app.png`: workspace/sidebar and shared Files page.
- `annotation-export.png`: full-resolution exported PNG, inspected against the on-screen annotation.
- October 13 adds `file-drag-left.png`, `file-drag-right.png` and `file-attached.png`: expanded receiver positions/background and final file context. The two-axis follow correction also exports `file-drag-top.png`, `file-drag-bottom.png`, `file-drag-top-left.png`, `file-drag-bottom-right.png` and `file-drag-reduced-motion.png`, bringing the file/capture fixture set to seventeen outputs. Toni and the coral light share the same position; captions sit below the outlined moving area. These are static layout captures; the actual intake is exported separately in `../file-reception/toni-file-receive.mp4`.

- October 13 AI ownership correction adds `ada-ai-idle.png`, `ada-ai-active.png` and `ada-ai-compact.png` with owned analytics fixtures. Ada represents coding work in the AI dashboard and compact island, while provider brand icons stay unchanged. The generator now exports twenty images. No real sessions or account history are read.

Native AppKit text fields/pickers, drag providers, scroll views and some checkboxes are substituted with static equivalents only in `islandPreview`. ImageRenderer cannot render those platform views reliably. The actual app retains its native controls. Quick Look, ShareLink, actual permission dialogs, drag transfer and native capture are manual acceptance items, not proved by these stills. A bounded island page scrolls in the actual app; a still cannot show its lower scroll content.

Regenerate from `Sieghart/` with `bash Tests/render-sprint-5-preview.sh`. The temporary downloads fixtures are removed after rendering. This folder and the tests are outside the final application bundle.
