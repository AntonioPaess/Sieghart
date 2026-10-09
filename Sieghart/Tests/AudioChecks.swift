import Foundation
import CoreAudio

@MainActor private final class MockAudio: AudioBackend {
    var reading = AudioSnapshot(devices: [AudioDeviceInfo(id: 1, name: "Output", uid: "out", inputChannels: 0, outputChannels: 2), AudioDeviceInfo(id: 2, name: "Input", uid: "in", inputChannels: 1, outputChannels: 0), AudioDeviceInfo(id: 3, name: "Headphones", uid: "other", inputChannels: 0, outputChannels: 2)], apps: [AudioApplicationInfo(id: "test.app", name: "Player", processes: [11], pid: 99)], output: 1, input: 2, outputVolume: 0.5, inputVolume: 0.8, inputMuted: false)
    var routes: [String: Float] = [:]
    var appliedProcesses: [String: [AudioObjectID]] = [:]
    var stopped = 0
    var fail = false
    var calls = 0
    var permissionRequests = 0
    var permissionFailure: OSStatus?
    var pending: CheckedContinuation<Void, Never>?
    var holdsRequest = false
    func prepareApplicationAudio() async throws {
        permissionRequests += 1
        if holdsRequest { await withCheckedContinuation { pending = $0 } }
        if let status = permissionFailure { throw AudioFailure(operation: "Permission fixture", status: status) }
    }
    func snapshot() -> AudioSnapshot { reading }
    func setVolume(_ value: Float, device: AudioObjectID, input: Bool) throws { if input { reading.inputVolume = value } else { reading.outputVolume = value } }
    func setDefault(_ device: AudioObjectID, input: Bool) throws { if fail { throw AudioFailure(operation: "Fixture", status: -1) }; if input { reading.input = device } else { reading.output = device } }
    func setInputMuted(_ muted: Bool, device: AudioObjectID) throws { reading.inputMuted = muted }
    func setApplication(_ app: AudioApplicationInfo, gain: Float, output: AudioDeviceInfo) throws {
        calls += 1
        if fail { throw AudioFailure(operation: "Fixture", status: -1) }
        routes[app.id] = gain; appliedProcesses[app.id] = app.processes
    }
    func retainApplications(_ ids: Set<String>) { routes = routes.filter { ids.contains($0.key) } }
    func stopApplications() { stopped += 1; routes = [:] }
}
private final class Buffers {
    let list: UnsafeMutableAudioBufferListPointer
    let samples: [UnsafeMutablePointer<Float>]
    init(_ contents: [[Float]], channels: [UInt32]) {
        let storage = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AudioBufferList>.size + (contents.count - 1) * MemoryLayout<AudioBuffer>.stride, alignment: MemoryLayout<AudioBufferList>.alignment)
        let pointer = storage.assumingMemoryBound(to: AudioBufferList.self)
        pointer.pointee.mNumberBuffers = UInt32(contents.count)
        list = UnsafeMutableAudioBufferListPointer(pointer)
        samples = contents.map { values in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, values.count))
            pointer.initialize(from: values, count: values.count); return pointer
        }
        for index in contents.indices { list[index] = AudioBuffer(mNumberChannels: channels[index], mDataByteSize: UInt32(contents[index].count * 4), mData: samples[index]) }
    }
    func values(_ index: Int, count: Int) -> [Float] { Array(UnsafeBufferPointer(start: samples[index], count: count)) }
    deinit { for sample in samples { sample.deallocate() }; list.unsafeMutablePointer.deallocate() }
}
@main struct AudioChecks {
    @MainActor static func main() async {
        let parents: [pid_t: pid_t] = [77: 50, 50: 12, 90: 91, 91: 90]
        precondition(AudioAppIdentity.ancestor(of: 77, isApplication: { $0 == 12 }, parent: { parents[$0] ?? 0 }) == 12, "Audio helpers must resolve to the visible app")
        precondition(AudioAppIdentity.ancestor(of: 90, isApplication: { _ in false }, parent: { parents[$0] ?? 0 }) == nil, "Cycles and daemons must not become mixer apps")
        let regular: Set<pid_t> = [12, 19]
        let responsible: [pid_t: pid_t] = [77: 12, 78: 19, 88: 50]
        func resolve(_ pid: pid_t, lookup: ((pid_t) -> pid_t?)? = nil) -> pid_t? {
            let resolver = lookup ?? { responsible[$0] }
            return AudioAppIdentity.applicationPID(of: pid, isApplication: regular.contains,
                parent: { [50: 12, 79: 50][$0] ?? 1 }, responsible: resolver)
        }
        precondition(resolve(77) == 12 && resolve(78) == 19,
                     "Shared WebKit XPC helpers must belong to their actual host, not all to Safari")
        precondition(resolve(88) == 12, "Responsibility may point to another helper, so follow its ancestry")
        precondition(resolve(79, lookup: { _ in nil }) == 12, "Missing SPI retains public ancestry fallback")
        precondition(resolve(79, lookup: { $0 }) == 12, "Self-responsible helpers still follow their parents")
        precondition(resolve(80, lookup: { _ in -1 }) == nil && resolve(81, lookup: { _ in 999 }) == nil,
                     "Unknown ownership must not borrow another browser's audio")
        precondition(resolve(12, lookup: { _ in 19 }) == 12 && resolve(1) == nil)
        precondition(AudioDeviceInfo(id: 1, name: "AirPods Pro", uid: "fixture", inputChannels: 1, outputChannels: 2, transport: kAudioDeviceTransportTypeBluetooth).symbol == "airpodspro")
        precondition(AudioDeviceInfo(id: 1, name: "Wireless headphones", uid: "fixture", inputChannels: 0, outputChannels: 2, transport: kAudioDeviceTransportTypeBluetooth).symbol == "headphones")
        let suite = "Sieghart.AudioChecks.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = MockAudio(), audio = AudioViewModel(backend: backend, defaults: defaults)
        precondition(backend.calls == 0 && !audio.perAppEnabled)
        audio.refresh(); let app = audio.state.apps[0]
        audio.setGain(0.4, app: app); precondition(backend.calls == 0, "No app capture before explicit enable")
        await audio.enableApplications(); precondition(backend.calls == 0 && backend.permissionRequests == 1 && audio.access == .ready)
        let waiting = AudioApplicationInfo(id: "waiting", name: "Waiting app", processes: [], pid: 100, isPlaying: false)
        let beforeWaiting = backend.calls; audio.setGain(0.4, app: waiting)
        precondition(backend.calls == beforeWaiting && audio.gains[waiting.id] == nil, "An open app without an audio connection must never claim an effective mix")
        audio.setGain(0.4, app: app); precondition(audio.routedApps == [app.id] && backend.routes[app.id] == 0.4)
        audio.setGain(0, app: app); precondition(backend.routes[app.id] == 0)
        audio.setGain(4, app: app); precondition(backend.routes[app.id] == 1)
        audio.setVolume(-1); audio.setVolume(2, input: true); audio.muteInput(true)
        precondition(audio.state.outputVolume == 0 && audio.state.inputVolume == 1 && audio.state.inputMuted == true)
        backend.fail = true; audio.setGain(0.2, app: app)
        precondition(audio.gains[app.id] == 1 && audio.error != nil && audio.routedApps.contains(app.id), "A failed replacement retains its last applied gain")
        audio.selectDevice(3); precondition(audio.state.output == 1 && audio.error != nil && backend.routes.isEmpty)
        let calls = backend.calls; audio.refresh(); precondition(backend.calls == calls, "Failed saved routes aren't repeatedly retried")
        backend.fail = false; audio.selectDevice(3); precondition(audio.state.output == 3 && backend.routes[app.id] == 1)
        backend.reading.output = 1; let stopped = backend.stopped; audio.refresh(); precondition(backend.stopped > stopped)
        let oldStops = backend.stopped
        backend.reading.devices[0].sampleRate = 16000
        audio.refresh(); precondition(backend.stopped > oldStops, "An AirPods format change rebuilds routes even with the same device ID")
        backend.reading.apps = []; audio.refresh(); precondition(backend.routes.isEmpty && audio.routedApps.isEmpty)
        backend.reading.apps = (0..<8).map { AudioApplicationInfo(id: "app.\($0)", name: "App \($0)", processes: [UInt32($0 + 10)], pid: pid_t($0 + 100)) }
        audio.refresh(); precondition(audio.visibleApps.count == 5 && audio.visibleApps.map(\.id) == ["app.0", "app.1", "app.2", "app.3", "app.4"])
        backend.reading.apps = Array(backend.reading.apps.prefix(2)); audio.refresh()
        precondition(audio.visibleApps.count == 2, "The mixer never fills missing apps with placeholder columns")
        audio.disableApplications(); precondition(!audio.perAppEnabled && backend.routes.isEmpty)
        let orderedApps = audio.state.apps
        audio.toggleFavorite(orderedApps[1]); precondition(audio.visibleApps.first?.id == orderedApps[1].id)
        audio.toggleFavorite(orderedApps[0]); audio.moveApp(orderedApps[1], direction: -1)
        precondition(audio.favoriteApps.count == 2 && audio.visibleApps.first?.id == orderedApps[1].id, "Ordering favorites preserves favorite status")
        backend.reading.apps = []; audio.refresh(); precondition(audio.visibleApps.isEmpty, "Closed favorites must not fabricate towers")
        backend.reading.apps = orderedApps; audio.refresh()
        let headphones = backend.reading.devices[2]
        audio.preferDevice(headphones, input: false)
        let beforePriority = backend.reading.output
        audio.refresh(); precondition(backend.reading.output == beforePriority, "Saved priority is not automatic authorization")
        audio.automaticDevices = true; precondition(backend.reading.output == headphones.id)
        audio.selectDevice(1); audio.refresh(); precondition(audio.state.output == 1, "Keep a manual choice until topology changes")
        backend.reading.devices.removeLast(); audio.refresh()
        let reconnected = AudioDeviceInfo(id: 42, name: headphones.name, uid: headphones.uid, inputChannels: headphones.inputChannels, outputChannels: headphones.outputChannels)
        backend.reading.devices.append(reconnected); audio.refresh()
        precondition(audio.state.output == 42, "Reconnect resolves the same UID even with a different object ID")
        audio.cycleOutput(); precondition(audio.state.output == 1)
        let mutedBefore = audio.state.inputMuted!; audio.toggleMicrophoneMute(); precondition(audio.state.inputMuted == !mutedBefore)
        backend.reading.inputMuted = nil; audio.toggleMicrophoneMute(); precondition(audio.error != nil)
        audio.shutdown()
        let restored = AudioViewModel(backend: MockAudio(), defaults: defaults)
        precondition(restored.gains[app.id] == 1 && !restored.perAppEnabled && restored.favoriteApps.count == 2 && restored.outputPriority == [headphones.uid], "Saved gain must not authorize a new capture session")

        let deniedBackend = MockAudio(); deniedBackend.permissionFailure = kAudioDevicePermissionsError
        let denied = AudioViewModel(backend: deniedBackend, defaults: defaults)
        await denied.enableApplications()
        precondition(!denied.perAppEnabled && denied.access == .permissionRequired && deniedBackend.calls == 0, "No saved mix before the real permission request succeeds")
        deniedBackend.permissionFailure = nil; await denied.enableApplications()
        precondition(denied.perAppEnabled && deniedBackend.permissionRequests == 2)
        let delayedBackend = MockAudio(); delayedBackend.holdsRequest = true
        let delayed = AudioViewModel(backend: delayedBackend, defaults: defaults)
        let request = Task { await delayed.enableApplications() }
        while delayedBackend.pending == nil { await Task.yield() }
        precondition(delayed.access == .requesting && !delayed.perAppEnabled)
        delayed.disableApplications(); delayedBackend.pending?.resume(); await request.value
        precondition(delayed.access == .off && !delayed.perAppEnabled && delayedBackend.calls == 0, "An obsolete permission request must not enable capture")

        let mixerSuite = "Sieghart.AudioApps.\(UUID())", mixerDefaults = UserDefaults(suiteName: mixerSuite)!
        defer { mixerDefaults.removePersistentDomain(forName: mixerSuite) }
        let browserBackend = MockAudio(), mixer = AudioViewModel(backend: browserBackend, defaults: mixerDefaults)
        let safari = AudioApplicationInfo(id: "com.apple.Safari", name: "Safari", processes: [501], pid: 12)
        let finder = AudioApplicationInfo(id: "com.apple.finder", name: "Finder", processes: [900], pid: 19)
        browserBackend.reading.apps = [finder, safari] + (0..<5).map {
            AudioApplicationInfo(id: "player.\($0)", name: "Player \($0)", processes: [UInt32(600 + $0)], pid: pid_t(100 + $0))
        }
        mixer.refresh()
        precondition(mixer.visibleApps.count == 5 && !mixer.visibleApps.contains { $0.id == finder.id })
        await mixer.enableApplications()
        mixer.setGain(0.3, app: safari)
        let other = browserBackend.reading.apps[2]
        mixer.setGain(0.6, app: other)
        let newSafari = AudioApplicationInfo(id: safari.id, name: safari.name, processes: [502, 503], pid: 12)
        browserBackend.reading.apps[1] = newSafari
        mixer.setGain(0.2, app: safari) // The view still holds the old process group.
        precondition(browserBackend.appliedProcesses[safari.id] == [502, 503] && browserBackend.routes[safari.id] == 0.2,
                     "A slider change must tap the current browser helpers, even before the next poll")
        mixer.toggleFavorite(safari)
        mixer.hideApp(safari)
        precondition(mixer.hiddenApps == [HiddenAudioApplication(id: safari.id, name: safari.name)])
        precondition(mixer.visibleApps.count == 5 && !mixer.visibleApps.contains { $0.id == safari.id },
                     "Hiding refills the five-app cap from real eligible apps")
        precondition(browserBackend.routes[safari.id] == nil && browserBackend.routes[other.id] == 0.6)
        precondition(!mixer.routedApps.contains(safari.id) && mixer.gains[safari.id] == 0.2,
                     "Hide releases only that app's audio route and retains its saved choice")
        let hiddenCalls = browserBackend.calls
        mixer.setGain(0, app: safari)
        precondition(browserBackend.calls == hiddenCalls, "A removed row's stale callback cannot retap a hidden app")
        mixer.refresh()
        precondition(browserBackend.routes[safari.id] == nil && !mixer.visibleApps.contains { $0.id == safari.id })
        let reopened = AudioViewModel(backend: browserBackend, defaults: mixerDefaults)
        reopened.refresh()
        precondition(reopened.hiddenApps == mixer.hiddenApps && !reopened.perAppEnabled)
        precondition(!reopened.visibleApps.contains { $0.id == safari.id })
        mixer.restoreApp(safari.id)
        precondition(mixer.hiddenApps.isEmpty && mixer.visibleApps.first?.id == safari.id)
        precondition(browserBackend.routes[safari.id] == 0.2 && browserBackend.appliedProcesses[safari.id] == [502, 503])
        mixer.hideApp(safari)
        browserBackend.reading.apps.removeAll { $0.id == safari.id }
        mixer.restoreApp(safari.id)
        precondition(!mixer.visibleApps.contains { $0.id == safari.id } && browserBackend.routes[safari.id] == nil,
                     "Restoring a closed app never fabricates a tower")
        let staleCalls = browserBackend.calls
        mixer.setGain(0.1, app: safari)
        precondition(browserBackend.calls == staleCalls, "A closed browser's stale slider cannot receive a tap")
        mixer.setGain(0.2, app: finder)
        precondition(browserBackend.calls == staleCalls && !mixer.visibleApps.contains { $0.id == finder.id })
        mixer.shutdown()

        let stereo = Buffers([[1, -1, 0.5, -0.5, 0.2, -0.2]], channels: [2])
        let planar = Buffers([[9, 9], [9, 9]], channels: [1, 1])
        AudioPCM.render(input: stereo.list.unsafePointer, output: planar.list.unsafeMutablePointer, gain: 0.5)
        precondition(planar.values(0, count: 2) == [0.5, 0.25] && planar.values(1, count: 2) == [-0.5, -0.25], "Interleaved to planar, bounded by shorter output")
        let interleaved = Buffers([[9, 9, 9, 9, 9, 9]], channels: [2])
        AudioPCM.render(input: planar.list.unsafePointer, output: interleaved.list.unsafeMutablePointer, gain: 1)
        precondition(interleaved.values(0, count: 6) == [0.5, -0.5, 0.25, -0.25, 0, 0], "Planar to interleaved; unused frames must be cleared")
        AudioPCM.render(input: stereo.list.unsafePointer, output: interleaved.list.unsafeMutablePointer, gain: 0)
        precondition(interleaved.values(0, count: 6) == [0, 0, 0, 0, 0, 0], "Mute clears every output sample")
        let combined = Buffers([[0.99, 0.99], [0.6, -0.6, 0.2, -0.2]], channels: [1, 2])
        AudioPCM.render(input: combined.list.unsafePointer, output: interleaved.list.unsafeMutablePointer, gain: 0.5, sourceBufferOffset: 1)
        precondition(interleaved.values(0, count: 6) == [0.3, -0.3, 0.1, -0.1, 0, 0], "Hardware microphone buffers must never be mixed into app playback")
        let callStereo = Buffers([[0.8, 0.4, -0.6, -0.2]], channels: [2])
        let mono = Buffers([[9, 9]], channels: [1])
        AudioPCM.render(input: callStereo.list.unsafePointer, output: mono.list.unsafeMutablePointer, gain: 0.5)
        precondition(abs(mono.values(0, count: 2)[0] - 0.3) < 0.0001 && abs(mono.values(0, count: 2)[1] + 0.2) < 0.0001, "A Bluetooth call folds stereo channels without changing playback speed")
        let monoSource = Buffers([[0.4, -0.4]], channels: [1])
        AudioPCM.render(input: monoSource.list.unsafePointer, output: planar.list.unsafeMutablePointer, gain: 1)
        precondition(planar.values(0, count: 2) == [0.4, -0.4] && planar.values(1, count: 2) == [0.4, -0.4])
        print("Audio checks passed: browser/XPC responsibility and ancestry fallback, fresh helper groups, Finder exclusion, five real apps, persistent hide/restore with route release, AirPods/device symbols, explicit capture, routing failures, device switching, teardown, gain persistence, mute and bounded PCM layouts. No hardware used.")
    }
}
