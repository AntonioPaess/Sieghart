# Calendar with Gantt — October 12, 2026

These PNGs render the production SwiftUI views at 2× using injected Calendar/notification adapters. Event names, links and reminders are fixtures. No native app window, EventKit read, permission prompt or hardware service was used.

Run from the repository root:

```sh
bash Sieghart/Tests/render-calendar-preview.sh
```

The permission and denied states retain Gantt and an explicit access/settings button. The month grid fits the island's existing size; the actual island scrolls to reminders and notification preferences. The app/menu retain day/week/month controls. System-backed menu controls can appear as unsupported placeholders in ImageRenderer; those exports do not establish native menu interaction.

In the live app Gantt plays his three-second identity hello once on entering the page, then uses cached Retina artwork and Core Animation breathing. The renderer detaches at the handoff or when the view is removed. Reduce Motion keeps the character still. The PNGs show the idle pose, not elapsed animation frames.

Signed build for user testing: `/private/tmp/sieghart-team-build/Build/Products/Debug/Sieghart.app`. Check Calendar in app, menu and island, click a day/month arrow, join a meeting and create/snooze/complete a reminder. If Calendar consent is pending or denied, verify Gantt on that page and the real macOS access flow. Allow the brief hello to finish and compare CPU with the idle state. Whole-app CPU, physical consent and notification delivery remain user acceptance checks.

The revised greeting is at `../team-runtime/hello-companions.mp4`: 31 seconds, 1064×600, 60 fps, exported offscreen from the production choreography. The horizontal rectangle is removed; the circular halo and timing are preserved.
