import AppKit
import CoreAudio
import Combine
import os
import Darwin

@MainActor final class AudioViewModel: ObservableObject {
    @Published private(set) var state = AudioSnapshot()
    @Published private(set) var perAppEnabled = false
    @Published private(set) var access: AppMixerAccess = .off
    private var enableGeneration = 0
    @Published private(set) var routedApps: Set<String> = []
    @Published private(set) var gains: [String: Float] = [:]
    @Published private(set) var error: String?
    @Published private(set) var favoriteApps: [String] = []
    @Published private(set) var appOrder: [String] = []
    @Published private(set) var outputPriority: [String] = []
    @Published private(set) var inputPriority: [String] = []
    @Published var automaticDevices = false {
        didSet {
            defaults.set(automaticDevices, forKey: "audio.automaticDevices")
            if automaticDevices { refresh(); applyPriorities(); startPolling() }
        }
    }
    var onReaction: ((Bool) -> Void)?
    var visibleApps: [AudioApplicationInfo] {
        let positions = Dictionary(uniqueKeysWithValues: appOrder.enumerated().map { ($1, $0) })
        return Array(state.apps.enumerated().sorted { a, b in
            let af = favoriteApps.contains(a.element.id), bf = favoriteApps.contains(b.element.id)
            if af != bf { return af }
            return (positions[a.element.id] ?? (10_000 + a.offset)) < (positions[b.element.id] ?? (10_000 + b.offset))
        }.prefix(5).map(\.element))
    }
    private let backend: any AudioBackend
    private let defaults: UserDefaults
    private var poll: Task<Void, Never>?
    private var observers = 0
    private var failedApps: Set<String> = []

    init(backend: (any AudioBackend)? = nil, defaults: UserDefaults = .standard) {
        self.backend = backend ?? CoreAudioBackend()
        self.defaults = defaults
        gains = (defaults.dictionary(forKey: "audio.appGains") ?? [:]).compactMapValues { ($0 as? NSNumber)?.floatValue }.mapValues { min(1, max(0, $0)) }
        favoriteApps = defaults.stringArray(forKey: "audio.favoriteApps") ?? []
        appOrder = defaults.stringArray(forKey: "audio.appOrder") ?? []
        outputPriority = defaults.stringArray(forKey: "audio.outputPriority") ?? []
        inputPriority = defaults.stringArray(forKey: "audio.inputPriority") ?? []
        automaticDevices = defaults.bool(forKey: "audio.automaticDevices")
    }
    func refresh() {
        let latest = backend.snapshot()
        let previousOutput = state.devices.first { $0.id == state.output }
        let nextOutput = latest.devices.first { $0.id == latest.output }
        if latest.output != state.output || previousOutput != nextOutput { backend.stopApplications(); routedApps = []; failedApps = [] }
        // A restarted app/helper is a new route opportunity after a failure.
        failedApps = failedApps.filter { id in
            state.apps.first { $0.id == id }?.processes == latest.apps.first { $0.id == id }?.processes
        }
        let topologyChanged = Set(latest.devices.map(\.uid)) != Set(state.devices.map(\.uid))
        state = latest
        if automaticDevices && topologyChanged { applyPriorities() }
        let alive = Set(state.apps.filter { !$0.processes.isEmpty }.map(\.id))
        backend.retainApplications(alive); routedApps.formIntersection(alive)
        guard perAppEnabled, let output = state.devices.first(where: { $0.id == state.output }) else { return }
        for app in state.apps where !app.processes.isEmpty && gains[app.id] != nil && !failedApps.contains(app.id) {
            do { try backend.setApplication(app, gain: gains[app.id]!, output: output); routedApps.insert(app.id) }
            catch { routedApps.remove(app.id); failedApps.insert(app.id); self.error = error.localizedDescription }
        }
    }
    func observe() {
        observers += 1; refresh()
        startPolling()
    }
    func startLifecycle() { if automaticDevices { refresh(); startPolling() } }
    private func startPolling() {
        guard poll == nil else { return }
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
                if self.observers == 0 && !self.perAppEnabled && !self.automaticDevices { self.poll = nil; return }
            }
        }
    }
    func stopObserving() { observers = max(0, observers - 1) }
    func toggleFavorite(_ app: AudioApplicationInfo) {
        if favoriteApps.contains(app.id) { favoriteApps.removeAll { $0 == app.id } } else { favoriteApps.append(app.id) }
        defaults.set(favoriteApps, forKey: "audio.favoriteApps")
    }
    func moveApp(_ app: AudioApplicationInfo, direction: Int) {
        var order = visibleApps.map(\.id)
        let peers = order.filter { favoriteApps.contains($0) == favoriteApps.contains(app.id) }
        guard let peer = peers.firstIndex(of: app.id), peers.indices.contains(peer + direction),
              let index = order.firstIndex(of: app.id), let target = order.firstIndex(of: peers[peer + direction]) else { return }
        order.swapAt(index, target)
        appOrder = order + appOrder.filter { !order.contains($0) }
        defaults.set(appOrder, forKey: "audio.appOrder")
    }
    func canMoveApp(_ app: AudioApplicationInfo, direction: Int) -> Bool {
        let peers = visibleApps.filter { favoriteApps.contains($0.id) == favoriteApps.contains(app.id) }
        guard let index = peers.firstIndex(where: { $0.id == app.id }) else { return false }
        return peers.indices.contains(index + direction)
    }
    func preferDevice(_ device: AudioDeviceInfo, input: Bool, direction: Int = -1) {
        var list = input ? inputPriority : outputPriority
        if let index = list.firstIndex(of: device.uid) { if list.indices.contains(index + direction) { list.swapAt(index, index + direction) } }
        else { list.insert(device.uid, at: 0) }
        if input { inputPriority = list } else { outputPriority = list }
        defaults.set(list, forKey: input ? "audio.inputPriority" : "audio.outputPriority")
    }
    func removePriority(_ device: AudioDeviceInfo, input: Bool) {
        if input { inputPriority.removeAll { $0 == device.uid }; defaults.set(inputPriority, forKey: "audio.inputPriority") }
        else { outputPriority.removeAll { $0 == device.uid }; defaults.set(outputPriority, forKey: "audio.outputPriority") }
    }
    private func applyPriorities() {
        guard automaticDevices else { return }
        for input in [false, true] {
            let order = input ? inputPriority : outputPriority
            guard let device = order.compactMap({ uid in state.devices.first { $0.uid == uid && (input ? $0.inputChannels : $0.outputChannels) > 0 } }).first,
                  device.id != (input ? state.input : state.output) else { continue }
            do {
                if !input { backend.stopApplications(); routedApps = []; failedApps = [] }
                try backend.setDefault(device.id, input: input); state = backend.snapshot(); error = nil
            } catch { self.error = error.localizedDescription; onReaction?(false) }
        }
    }
    func cycleOutput() {
        refresh()
        let available = state.devices.filter { $0.outputChannels > 0 }
        guard available.count > 1 else { error = "Connect another output to switch devices"; onReaction?(false); return }
        let index = available.firstIndex { $0.id == state.output } ?? -1
        selectDevice(available[(index + 1) % available.count].id)
    }
    func toggleMicrophoneMute() {
        refresh()
        guard let muted = state.inputMuted else { error = "This microphone doesn't support hardware mute"; onReaction?(false); return }
        muteInput(!muted)
    }
    func shutdown() { poll?.cancel(); poll = nil; backend.stopApplications(); routedApps = [] }
    func enableApplications() async {
        guard access != .requesting, !perAppEnabled else { return }
        enableGeneration += 1
        let generation = enableGeneration
        access = .requesting; error = nil
        do {
            try await backend.prepareApplicationAudio()
            guard generation == enableGeneration else { return }
            perAppEnabled = true; access = .ready; failedApps = []; refresh()
        } catch {
            guard generation == enableGeneration else { return }
            perAppEnabled = false
            access = (error as? AudioFailure)?.status == kAudioDevicePermissionsError ? .permissionRequired : .failed
            self.error = error.localizedDescription
        }
    }
    func disableApplications() {
        enableGeneration += 1; backend.stopApplications(); perAppEnabled = false
        access = .off; routedApps = []; failedApps = []; error = nil
    }
    func openAudioPermissionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AudioCapture") else { return }
        NSWorkspace.shared.open(url)
    }
    func setVolume(_ value: Float, input: Bool = false) {
        perform { try backend.setVolume(min(1, max(0, value)), device: input ? state.input : state.output, input: input) }; state = backend.snapshot()
    }
    func selectDevice(_ id: AudioObjectID, input: Bool = false) {
        if !input { backend.stopApplications(); routedApps = []; failedApps = [] }
        perform { try backend.setDefault(id, input: input) }; refresh()
    }
    func muteInput(_ muted: Bool) { perform { try backend.setInputMuted(muted, device: state.input) }; state = backend.snapshot() }
    func setGain(_ value: Float, app: AudioApplicationInfo) {
        guard perAppEnabled, !app.processes.isEmpty, let output = state.devices.first(where: { $0.id == state.output }) else { return }
        let gain = min(1, max(0, value))
        do {
            try backend.setApplication(app, gain: gain, output: output)
            gains[app.id] = gain; routedApps.insert(app.id); failedApps.remove(app.id); error = nil
            defaults.set(gains, forKey: "audio.appGains")
        } catch {
            // A replacement can fail while an existing route still works.
            self.error = error.localizedDescription
            if (error as? AudioFailure)?.status == kAudioDevicePermissionsError {
                disableApplications(); access = .permissionRequired; self.error = error.localizedDescription
            }
        }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); error = nil; onReaction?(true) } catch { self.error = error.localizedDescription; onReaction?(false) } }
}
