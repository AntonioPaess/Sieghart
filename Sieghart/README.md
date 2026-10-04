# Sieghart

Native macOS SwiftUI project for the personal assistant previously referred to as MyDude.

Sieghart will bring together daily context, calendar, reminders, Pomodoro sessions, voice, AI integrations, and a physical trigger driven by impact detection from the Mac accelerometer.

## Current state

The project has a main window, a menu bar entry, a notch panel prototype, an experimental AppleSPUHIDDevice accelerometer reader, a Calendar/EventKit integration under real-device validation, configurable one-, two-, and three-impact actions, and a local Pomodoro action. The sensor starts automatically when the app opens. Two impacts can start or pause Pomodoro, and the focus widget shows a countdown orb on the right, animated arms, and a **Finish** button. Three impacts show Calendar mode without triggering a permission prompt; a **Show calendar in notch** action is also available from the main window and menu bar. Only the explicit **Connect calendar** action requests access. After authorization, an asynchronous EventKit query checks the next seven days and distinguishes no calendars, no upcoming events, and loaded events. A meeting URL from the event URL, location, or notes can be opened from the widget. The detector uses all three axes, a simple gravity baseline, and a cooldown to reduce repeated triggers.

The development environment confirmed a Mac15,7 with an Apple M3 Pro and an AppleSPUHIDDevice service using usage 3 with 22-byte reports. The app still needs to be run on the hardware to confirm actual sensor access, sampling behavior, and permission requirements.

The notch panel now derives the camera cutout width and top inset from `NSScreen`, draws a narrow neck that expands into the body below the physical notch, and animates the panel height from the top edge. Its hover target follows the measured cutout rather than covering a broad section of the menu bar. Reduce Motion disables the panel transition and continuous character motion. These geometry changes are a test candidate, not an accepted visual design. Pomodoro phase, deadline, and paused time are stored in `UserDefaults` so a session can recover after relaunch; full-session behavior still needs a real Mac test.

The project also builds for `x86_64`, but that only confirms binary compatibility. It does not mean that the Intel Mac has the required accelerometer.

## Current technical milestone

The Calendar integration still needs a real Mac test with a known event and meeting URL. A successful build and a granted authorization state do not establish that personal events load correctly. The notch appearance also requires the user's visual review on the actual display.

## Name

`Sieghart` is the current technical project name. `MyDude` remains the product concept name in the vault until the product identity is finalized.
