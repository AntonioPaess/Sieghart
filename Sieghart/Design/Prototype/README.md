# Sieghart — Design reference

Open `index.html` locally to explore the medium fidelity main-window and notch flows. The preview demonstrates focus duration, short/long breaks, rounds, and compact timer controls. Voice is simulated and does not access the microphone.

The native app now implements these controls. Later feedback added a dedicated Focus tab in the app, a retro CRT companion, a compact island during sessions, completion celebrations, and automatic voice commands. The HTML is an earlier design reference. Refer to the native implementation and [project README](../../README.md) for current behavior.

The preview’s focus setup was checked with a 50-minute duration, 10-minute short break, and 6 rounds, followed by starting and pausing. The screenshots in this folder depict the prototype, not the running native app.

[The Figma file](https://www.figma.com/design/g3iMvcEIJVyRojBn265cAa) remains incomplete because the Starter MCP quota interrupted text and layout repairs. The local prototype is the usable design reference.

`avatar-preview.png` is rendered from the current SwiftUI character, showing idle, focus, joyful, and listening expressions. It is an offscreen render, not a screenshot of the running widget.
