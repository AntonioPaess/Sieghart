# Sprint 4 — System utilities and companion greeting

October 8, 2026. The user accepted all tests of the previous clipboard/island/editor slice and authorized the remaining utilities. The implementation below is delivered. Its new physical Mac checks remain separate from that acceptance. Sieghart and Xcode were kept closed throughout development.

## Delivered

| Area | Implemented behavior |
| --- | --- |
| System | Two-second CPU counter deltas, exposed GPU utilization, app/wired/compressed memory, cache/swap detail, memory pressure and thermal state. Physical network byte rates/totals and local IPv4, mounted-volume free/capacity and exposed disk I/O, battery/charging/health/cycles/time and battery power draw, USB product names. Sixty-sample local history with exact hover readings. |
| Keep awake | Duration, future deadline or indefinite session; optional display assertion, AC/external-display/app conditions, pause/release on sleep or unmet conditions, stop/expiry/quit cleanup and opt-in restoration of valid sessions. One owned IOPM assertion, replaced only when its type changes. |
| Audio | Five real running apps plus Master; persisted favorites and order within favorite/ordinary groups. Closed favorites never create columns. UID-based output/input priorities, explicit automatic selection on connection topology changes and manual selection preserved between changes. Optional configurable global output-cycle and selected-microphone hardware-mute shortcuts, sharing collision checks and resident dispatch. Existing route recovery stays intact. |
| Display and power | Compatible native hardware brightness, bounded software dimming with original color-table restoration, explicit display sleep, reported HDR headroom, opt-in Bluetooth device disconnect during sleep and asynchronous authenticated reconnection only for devices successfully disconnected by Sieghart. Opt-in Music launch prevention limited to a newly launched Music app within two seconds of a detected playback key. |
| Companion | Successful/error utility reactions and sustained-load/low-battery/critical-memory feedback without forcing the island open. Original native greeting: center drop, landing squash, lateral drift, brief wave, return and docking into Companion while content fades in. Runs after onboarding and optionally on app launch; tapping interrupts. Reduce Motion/Character motion off show the final state. |
| Surfaces | System, Keep awake and Display & power in the app, island page menu, tool launcher and editable rails. Menu-bar overflow opens compact subpages. Ten launcher tiles fit two rows; the launcher height is retained. Glass remains independently configurable and off by default. |

## Hardware boundaries

- GPU counters appear only if IOKit exposes utilization. Numeric CPU/GPU temperatures, fan RPM/control, per-process network traffic, speed testing and SMART health are not implemented by this base monitor. Thermal *state* is reported separately, without inventing degrees or RPM.
- Power is the battery's reported voltage/current draw, not whole-system or wall-socket measurement. Desktop Macs without that source show unavailable.
- Preventing idle sleep does not override forced sleep, battery shutdown or unsupported closed-lid behavior. Supported docked clamshell operation still follows macOS requirements.
- Native brightness dynamically resolves a Mac-only DisplayServices capability and fails closed when absent. Software dimming adjusts an owned gamma table and restores it on sleep/quit; it is not a backlight increase. HDR headroom is informational; an XDR desktop boost is **not delivered**. Private/unsupported desktop adapters require review or omission for future Challenge packaging.
- Bluetooth restoration requests a connection asynchronously; an offline/rejected device reports failure. It does not toggle the Bluetooth radio or connect devices that were already disconnected. macOS can show its real Bluetooth permission prompt when this optional feature is used.
- Music prevention needs Accessibility for playback-key observation. Existing Music sessions and ordinary manual launches outside the two-second playback window remain running. This is a narrow heuristic, not a claim to identify every possible automatic launch.

## Verification

Twelve isolated check groups cover the existing workflows and new counter resets/rates, bounded monitor history, assertion ownership, AC/display/app conditions, sleep/expiry/relaunch, brightness failures, dimming limits, Bluetooth ownership, Music timing, favorites/order, real-app caps, reconnect UID changes, manual output choice, shortcut collisions/persistence and interrupted contour geometry. Native artwork is sampled continuously and reduced-motion defaults are checked. Hardware adapters are injected; no real clipboard, audio, Bluetooth, display write, power assertion, microphone, sensor or shortcut is used.

The universal arm64/x86_64 app is built with CLI tools and its actual package is checked for privacy descriptions, resident-agent metadata and signature. Production UI previews use fixture readings and are explicitly examples, not captures of the user's device.

## New Mac checks

1. **System:** open the app's System page or island → System. Wait two samples, check CPU/network change with real work, memory detail on hover, Disks capacity and History tooltips. Missing GPU/power readings must say unavailable. Closing the page stops its polling when no other System surface is visible.
2. **Keep awake:** start five minutes, then Stop. Repeat with Keep display awake, a future Until time, AC-only, external-display-only and a selected app. Unplug power or quit the selected app: status should become Waiting, then resume when the conditions return. Enable Resume valid session and relaunch during an unexpired session. Test sleep/wake and expiry. Closing the settings window must keep the resident session; Quit releases it.
3. **Audio:** play real audio, favorite and reorder apps through their icon's menu, close a favorite and verify it disappears. At most five actual apps plus Master remain. In Devices, rank connected AirPods/other devices, enable preferred devices, disconnect/reconnect them and check selection. Make a manual choice and verify it stays until the device list changes.
4. **Audio shortcuts:** in the app's Audio page, record distinct Switch output and Microphone mute chords. Test with the main window closed and another app in full screen. Output cycles connected outputs; microphone mute toggles only if that input exposes hardware mute. Denied/unsupported controls must report it. Restore shortcuts remains available in Activation.
5. **Display & power:** adjust compatible Brightness; unsupported hardware offers Dimming. Adjust dimming and Restore, then test sleep/wake and Quit restoration. Sleep displays should affect the displays only. HDR text must not claim an XDR boost. Optional Bluetooth sleep should reconnect only devices the app disconnected; test an unavailable device as well. Optional Music prevention should request Accessibility and suppress a new playback-key-triggered Music launch while leaving existing sessions intact.
6. **Companion:** Finish onboarding and relaunch with Launch greeting enabled. Watch the center drop/wave/dock, tap during it, navigate to another tool while opening and reverse opening/closing quickly. No delayed greeting should replace the chosen page. Test both motion settings and macOS Reduce Motion. Utility success/failure should react without automatically starting focus or opening a dismissed island.

## Next roadmap work

New hardware acceptance closes this delivery's release gate. Extended hardware functions listed above remain explicit backlog items. The next product sprint covers calendar/reminders, notifications, chosen-folder downloads, file shelf and capture. File receive/upload/email, connected chats and specialist agents are recorded later companion workflows; no external send is performed by this delivery.

## Previews

![System island](Concepts/island-system-preview.png)

[System app](Concepts/app-system-preview.png) · [Keep awake](Concepts/app-keep-awake-preview.png) · [Display and power](Concepts/app-display-power-preview.png) · [tool launcher](Concepts/island-tools-sprint4-preview.png) · [six-companion greeting](Concepts/companion-launch-greeting.gif).
