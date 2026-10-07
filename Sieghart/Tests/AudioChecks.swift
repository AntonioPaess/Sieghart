import Foundation
import CoreAudio

@MainActor private final class MockAudio: AudioBackend {
    var reading = AudioSnapshot(devices: [AudioDeviceInfo(id: 1, name: "Output", uid: "out", inputChannels: 0, outputChannels: 2), AudioDeviceInfo(id: 2, name: "Input", uid: "in", inputChannels: 1, outputChannels: 0), AudioDeviceInfo(id: 3, name: "Headphones", uid: "other", inputChannels: 0, outputChannels: 2)], apps: [AudioApplicationInfo(id: "test.app", name: "Player", processes: [11], pid: 99)], output: 1, input: 2, outputVolume: 0.5, inputVolume: 0.8, inputMuted: false)
    var routes: [String: Float] = [:]
    var stopped = 0
    var fail = false
    var calls = 0
    func snapshot() -> AudioSnapshot { reading }
    func setVolume(_ value: Float, device: AudioObjectID, input: Bool) throws { if input { reading.inputVolume = value } else { reading.outputVolume = value } }
    func setDefault(_ device: AudioObjectID, input: Bool) throws { if fail { throw AudioFailure(operation: "Fixture", status: -1) }; if input { reading.input = device } else { reading.output = device } }
    func setInputMuted(_ muted: Bool, device: AudioObjectID) throws { reading.inputMuted = muted }
    func setApplication(_ app: AudioApplicationInfo, gain: Float, output: AudioDeviceInfo) throws { calls += 1; if fail { throw AudioFailure(operation: "Fixture", status: -1) }; routes[app.id] = gain }
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
    @MainActor static func main() {
        let parents: [pid_t: pid_t] = [77: 50, 50: 12, 90: 91, 91: 90]
        precondition(AudioAppIdentity.ancestor(of: 77, isApplication: { $0 == 12 }, parent: { parents[$0] ?? 0 }) == 12, "Audio helpers must resolve to the visible app")
        precondition(AudioAppIdentity.ancestor(of: 90, isApplication: { _ in false }, parent: { parents[$0] ?? 0 }) == nil, "Cycles and daemons must not become mixer apps")
        precondition(AudioDeviceInfo(id: 1, name: "AirPods Pro", uid: "fixture", inputChannels: 1, outputChannels: 2, transport: kAudioDeviceTransportTypeBluetooth).symbol == "airpodspro")
        precondition(AudioDeviceInfo(id: 1, name: "Wireless headphones", uid: "fixture", inputChannels: 0, outputChannels: 2, transport: kAudioDeviceTransportTypeBluetooth).symbol == "headphones")
        let suite = "Sieghart.AudioChecks.\(UUID())", defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = MockAudio(), audio = AudioController(backend: backend, defaults: defaults)
        precondition(backend.calls == 0 && !audio.perAppEnabled)
        audio.refresh(); let app = audio.state.apps[0]
        audio.setGain(0.4, app: app); precondition(backend.calls == 0, "No app capture before explicit enable")
        audio.enableApplications(); precondition(backend.calls == 0)
        audio.setGain(0.4, app: app); precondition(audio.routedApps == [app.id] && backend.routes[app.id] == 0.4)
        audio.setGain(0, app: app); precondition(backend.routes[app.id] == 0)
        audio.setGain(4, app: app); precondition(backend.routes[app.id] == 1)
        audio.setVolume(-1); audio.setVolume(2, input: true); audio.muteInput(true)
        precondition(audio.state.outputVolume == 0 && audio.state.inputVolume == 1 && audio.state.inputMuted == true)
        backend.fail = true; audio.setGain(0.2, app: app)
        precondition(audio.gains[app.id] == 1 && audio.error != nil && !audio.routedApps.contains(app.id), "Failed controls must not claim applied gain")
        audio.selectDevice(3); precondition(audio.state.output == 1 && audio.error != nil && backend.routes.isEmpty)
        let calls = backend.calls; audio.refresh(); precondition(backend.calls == calls, "Failed saved routes aren't repeatedly retried")
        backend.fail = false; audio.selectDevice(3); precondition(audio.state.output == 3 && backend.routes[app.id] == 1)
        backend.reading.output = 1; let stopped = backend.stopped; audio.refresh(); precondition(backend.stopped > stopped)
        backend.reading.apps = []; audio.refresh(); precondition(backend.routes.isEmpty && audio.routedApps.isEmpty)
        audio.disableApplications(); precondition(!audio.perAppEnabled && backend.routes.isEmpty)
        let restored = AudioController(backend: MockAudio(), defaults: defaults)
        precondition(restored.gains[app.id] == 1 && !restored.perAppEnabled, "Saved gain must not authorize a new capture session")

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
        print("Audio checks passed: app/helper identity, AirPods/device symbols, explicit capture, routing failures, device switching, teardown, gain persistence, mute and bounded PCM layouts. No hardware used.")
    }
}
