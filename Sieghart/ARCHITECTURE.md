# Architecture

Updated October 8, 2026. SwiftUI presentation follows MVVM by feature, with protocol-injected native adapters. The physical directories and Xcode groups use the same hierarchy.

```text
Sieghart/Sieghart/
├── App/                        Application composition and resident lifecycle
├── Features/
│   ├── AIUsage/                AI dashboard and quota/details screens
│   ├── Audio/                  Mixer, devices and microphone
│   ├── Clipboard/              History and preferences
│   ├── DynamicIsland/          Widget view and presentation coordinator
│   ├── IslandLayout/           Visual button/layout editor
│   ├── Onboarding/             First-run view and consent/selection state
│   ├── Workspace/              Main-window navigation
│   ├── MenuBar/                Menu subpage navigation
│   ├── Timers/                 Focus, countdown and stopwatch
│   ├── SystemMonitor/          Monitor screen and readings/history state
│   ├── KeepAwake/              Keep-awake screen and session state
│   ├── DisplayPower/           Display/power screen and settings state
│   ├── ImpactGestures/         Optional sensor feature state
│   └── Calendar/               Existing calendar state for the upcoming feature
│       ├── Views/              SwiftUI screens and feature-specific subviews
│       └── ViewModels/         Observable state and user actions
├── Core/
│   ├── Services/               Platform/data adapters and their value contracts
│   │   ├── Voice/              PCM activity, speech authorization and session policy
│   │   ├── Audio/              Core Audio devices/process-tap adapter
│   │   ├── AI/                 Local usage readers, imports and pricing
│   │   ├── Clipboard/          Pasteboard access and bounded local storage
│   │   ├── System/             Native monitor sampling
│   │   ├── Power/              Owned power assertions
│   │   ├── Display/            Compatible display/power adapters
│   │   ├── Input/              Sensor reader
│   │   ├── Calendar/           EventKit data adapter
│   │   └── Windowing/          Native island panels and hit target
│   └── Helpers/                Voice parsing, URL encoding, shortcuts, timer/notch rules
└── Shared/
    ├── Components/             Reusable controls, styles, provider marks and avatars
    ├── Models/                 Common appearance/layout options
    ├── Services/               Preferences, resident activation and gesture coordinators
    └── Resources/              Provider assets and bundled pricing
```

Each screen feature keeps its View and ViewModel together in its own directory, with separate `Views` and `ViewModels` subdirectories. Several subviews can share one feature ViewModel; stateless reusable controls do not get empty wrapper ViewModels. Animation/hover and short-lived editor drafts can still use SwiftUI `@State`.

- **Views** render state and forward user actions. Workspace, menu, onboarding and layout navigation state now has explicit feature ViewModels.
- **ViewModels** own observable feature state and actions. Audio, clipboard, monitor, keep-awake, display, quota and AI usage types are consistently named `…ViewModel`.
- **Core** contains platform/data work and pure helpers. It does not reference feature ViewModels. Existing value contracts live next to the adapters that consume them.
- **Shared** contains components and services used by more than one feature. Activation is shared because the app, menu and island use the same resident shortcut/voice session; it is not a second voice screen.
- **App** builds and injects the shared instances, and owns application lifetime.

Native AppKit presentation still needs a coordinator. `NotchWidgetViewModel` coordinates panel ordering/geometry as well as presentation state; native panels/hit targets are separated in Core, but this is not a claim that every window operation has already moved behind a protocol. Future connected agents should have separate task state, tool adapters and animation mapping rather than expanding that coordinator or `ActivationController`.

## Verification

`Tests/run-checks.sh` resolves the new hierarchy and excludes App composition. Existing timer, AI, clipboard, audio and utility fixtures use injected dependencies; no app window or live permission/hardware activation is needed. The Xcode source/resource references follow real paths. Stored preference keys and bundled resource names are unchanged.
