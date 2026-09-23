# Sieghart

Native macOS SwiftUI project for the personal assistant previously referred to as MyDude.

Sieghart will bring together daily context, calendar, reminders, Pomodoro sessions, voice, AI integrations, and a physical trigger driven by impact detection from the Mac accelerometer.

## Current state

The project has a main window, a menu bar entry, a native opaque panel joined to the top edge near the notch, an experimental AppleSPUHIDDevice accelerometer reader, a read-only calendar context card, configurable one-, two-, and three-impact actions, and a local Pomodoro action. The sensor starts automatically when the app opens. Two impacts can start or pause Pomodoro, and the focus widget shows a countdown orb on the right, animated arms, and a **Finish** button. Three impacts can show the calendar mode with animated upcoming-event rows. The calendar mode includes its own **Connect calendar** action when permission is missing. The detector uses all three axes, a simple gravity baseline, and a cooldown to reduce repeated triggers.

The development environment confirmed a Mac15,7 with an Apple M3 Pro and an AppleSPUHIDDevice service using usage 3 with 22-byte reports. The app still needs to be run on the hardware to confirm actual sensor access, sampling behavior, and permission requirements.

The project also builds for `x86_64`, but that only confirms binary compatibility. It does not mean that the Intel Mac has the required accelerometer.

## Current technical milestone

Run Sieghart on the MacBook Pro M3 Pro and verify that the sensor is active without pressing a start button. Confirm that the widget stays hidden until the pointer enters the notch zone or an impact is detected, and that the visible panel is flush with the top edge instead of appearing behind or below the notch. Test the configurable one-, two-, and three-impact actions, then use the calendar widget's **Connect calendar** action to verify permission handling and the next-event link.

## Name

`Sieghart` is the current technical project name. `MyDude` remains the product concept name in the vault until the product identity is finalized.
