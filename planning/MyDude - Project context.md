---
title: MyDude - Project context
date: 2026-09-20
tags: [mydude, context, project, macos, swift-student-challenge, sensors]
created_by: project record
links: [[Projects - Index]], [[Career Map]]
---

# MyDude - Project context

## What it is

A personal Mac assistant with a visual face (reference: an emoji-style mascot with eyes and a smile; see the saved visual reference `IMG_4653.PNG`) that uses the Mac's internal accelerometer or IMU to detect configurable physical impacts near the trackpad. Each validated pattern can trigger a useful, customizable action.

## Problem and motivation

Make quick Mac actions possible without complex keyboard shortcuts or menu navigation: use physical impacts near the trackpad together with a visual companion assistant that can surface the day's context and carry out approved actions.

## Core concept

- Configurable impact patterns trigger user-defined actions.
- Calendar, reminders, Pomodoro sessions, daily context, and optional service connectors.
- A visual assistant presence near the notch or in a compact window.
- Optional future iPhone or Apple Watch companion for consented health context.

## Competitive goal

The Challenge is the first target, followed by a broader macOS product. The sensor is the required differentiator for the Challenge experience.

## Platform

- macOS (AppKit and SwiftUI)
- Possible iPhone or watchOS companion with HealthKit, posture signals, and explicit transfer
- AppleSPUHIDDevice impact reader, with low-level IOKit HID exploration

## Current state (2026-09-20)

- Initial concept defined around a visual mascot reference.
- The native Xcode project is `Sieghart.xcodeproj`.
- The prototype includes a main window, a menu bar entry, an experimental AppleSPUHIDDevice reader, visible report diagnostics, a configurable impact-action layer, and a local Pomodoro action.
- The current phase adds a native AppKit panel joined to the top edge near the notch with a face-first animated character, plus a read-only EventKit calendar card.
- The first hardware run exposed a zero-report case; the reader now filters the SPU accelerometer, derives its report buffer, attempts a best-effort driver wake, and reports the number of callbacks received.
- The M3 Pro retest succeeded: 4,992 reports and 17 impacts were observed. The sensor path is now separated from action routing so a single impact does not start or pause Pomodoro unless that mapping is selected.
- The default impact mappings are one impact to show or hide the character, two impacts to start or pause Pomodoro, and three impacts to show the calendar. Each mapping is editable in the main window and stored locally in UserDefaults.
- While Pomodoro is focusing, the widget places a countdown orb to the right of the character, adds animated focus arms, and offers a **Finish** button. The widget stays sticky during the focus phase and can be revealed again by hovering over the notch after a manual hide.
- The calendar gesture requests permission when needed and then opens the widget in a calendar mode with animated calendar presentation and upcoming events. The calendar mode includes a direct permission button when access is missing, and the permission request activates the app so the system sheet can be shown reliably.
- The widget uses a fully opaque black surface without a shadow and derives its horizontal center from the display's auxiliary top areas when available, keeping the visible shape joined to the notch instead of letting the window underneath bleed through.
- The widget now uses a window level above the main menu surface (`mainMenu + 3`) and joins all applications and Spaces, keeping the panel in front of the notch. Its reveal combines a short AppKit opacity animation with a SwiftUI spring scale anchored at the top edge, while the content is clipped to a straight-top, rounded-bottom shape.
- The panel remains anchored to the display's absolute top edge at its full 300-point width, placing the black surface behind the physical notch. Its height is 196 points, extending the bottom farther down without producing a narrow notch over a separate rectangular panel.
- The first global mouse hover monitor made the system unresponsive on launch; it was removed and replaced with a bounded AppKit tracking panel restricted to the notch zone.
- The current gate is runtime validation of the notch panel and calendar permission flow, followed by calibration and compatibility testing on the Intel i9 and M5 Air before making the sensor a trigger for more consequential actions.

## Related

- [[Projects - Index]]
- [[Career Map]] — relevant to the O-1A portfolio and the next Swift Student Challenge cycle
