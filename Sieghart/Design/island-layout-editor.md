# Visual island layout editor

October 8, 2026. The user supplied a visual settings reference and narrowed this follow-up to the editor design. The reported configuration-button issue was withdrawn before any changes to window opening; the activation/window route is untouched.

## Delivered

- Dedicated **Dynamic Island** sidebar page and **Appearance → Edit layout** entry.
- Central island/selected-companion miniature inside a spacious rounded canvas. Surrounding controls occupy the same three left/three right positions as the actual island. The miniature is a design preview; it invokes no pictured utility.
- Click an occupied circle to change its action or Remove button. Empty positions use dashed + circles. Drag to another occupied position to swap, or an empty position to move. Drop targets highlight; unrecognized drag payloads are rejected. Existing keyboard/accessibility button actions remain available, so dragging is optional.
- **Layout** offers Essentials, Focus and Work. Existing settings persist and duplicate actions swap; no new default layout replaces the user's saved choices.
- **Small / Medium / Large** visual size cards below the canvas use the existing saved widget sizes. Physical camera-band height remains unchanged. Optional **Liquid Glass** stays off by default and uses the existing independent setting.
- The bottom companion opens the existing six-avatar picker. All surfaces use the same selected native artwork and Sieghart palette. The editor has no new automatic focus/voice/hardware action.

## Verification

Signed universal CLI build and built-package verification passed. Existing isolated clipboard/preferences checks passed, including stored presets, swaps and hidden positions. Dark/light production-view previews were rendered offscreen; native drag/drop hosting is replaced by the same static drawn controls only in that renderer. Live controls keep their native handlers. No Sieghart/Xcode window or real hardware was opened.

## Manual check

1. Open **Dynamic Island** from the sidebar or **Appearance → Edit layout**.
2. Click a circle, remove it, then click its + and choose Clipboard. Expect the circle to return with the Clipboard icon.
3. Drag between occupied positions (swap), then into an empty position (move). The same settings should remain after relaunch and appear on the real island.
4. Try the three Layout presets and size cards. Click the bottom companion and choose another avatar. Glass should only change when selected.

The supplied screenshot is preserved as [reference pixels](References/Widget/2026-10-08-13-32-54-island-layout-editor-reference.png), outside the app resources. The current native [dark](Concepts/app-island-editor-dark-preview.png) and [light](Concepts/app-island-editor-light-preview.png) layouts are illustrative offscreen renders. Native drag/popover interaction needs the user's Mac check. Sprint 4 remains in progress with its previously recorded utility work.
