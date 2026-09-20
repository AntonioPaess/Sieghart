# Sieghart

Native macOS SwiftUI project for the personal assistant previously referred to as MyDude.

Sieghart will bring together daily context, calendar, reminders, Pomodoro sessions, voice, AI integrations, and a physical trigger driven by impact detection from the Mac accelerometer.

## Current state

The project has a main window, a menu bar entry, an experimental AppleSPUHIDDevice accelerometer reader, and a first local Pomodoro action. The detector uses all three axes, a simple gravity baseline, and a cooldown to reduce repeated triggers.

The development environment confirmed a Mac15,7 with an Apple M3 Pro and an AppleSPUHIDDevice service using usage 3 with 22-byte reports. The app still needs to be run on the hardware to confirm actual sensor access, sampling behavior, and permission requirements.

The project also builds for `x86_64`, but that only confirms binary compatibility. It does not mean that the Intel Mac has the required accelerometer.

## Current technical milestone

Run Sieghart on the MacBook Pro M3 Pro, press **Start sensor**, and document whether the device opens, the observed sampling rate, resource use, and false positives before connecting the sensor to more assistant actions.

## Name

`Sieghart` is the current technical project name. `MyDude` remains the product concept name in the vault until the product identity is finalized.
