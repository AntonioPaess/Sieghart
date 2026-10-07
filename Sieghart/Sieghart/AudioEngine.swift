import AppKit
import CoreAudio
import Combine
import os
import Darwin

struct AudioDeviceInfo: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let uid: String
    let inputChannels: Int
    let outputChannels: Int
    var transport: UInt32 = 0
    var symbol: String {
        let label = name.lowercased()
        if label.contains("airpods") { return label.contains("max") ? "airpodsmax" : label.contains("pro") ? "airpodspro" : "airpods" }
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE { return "headphones" }
        return outputChannels > 0 ? "speaker.wave.2" : "mic"
    }
}
struct AudioApplicationInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let processes: [AudioObjectID]
    let pid: pid_t
    var bundlePath: String? = nil
    var isPlaying = true
}

// Public process ancestry and installed app bundles resolve browser/audio helpers
// to their visible app. No private responsibility symbol or app-specific list.
enum AudioAppIdentity {
    static func ancestor(of pid: pid_t, isApplication: (pid_t) -> Bool, parent: (pid_t) -> pid_t) -> pid_t? {
        var current = pid, visited: Set<pid_t> = []
        for _ in 0..<32 {
            guard current > 1, visited.insert(current).inserted else { return nil }
            if isApplication(current) { return current }
            current = parent(current)
        }
        return nil
    }
    @MainActor static func owner(of pid: pid_t) -> NSRunningApplication? {
        if let id = ancestor(of: pid, isApplication: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular }, parent: { id in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            return proc_pidinfo(id, PROC_PIDTBSDINFO, 0, &info, size) == size ? pid_t(info.pbi_ppid) : 0
        }) { return NSRunningApplication(processIdentifier: id) }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, let bundle = app.bundleURL?.path else { return false }
            return executable.hasPrefix(bundle + "/")
        }.max { ($0.bundleURL?.path.count ?? 0) < ($1.bundleURL?.path.count ?? 0) }
    }
    @MainActor static func icon(for app: AudioApplicationInfo) -> NSImage? {
        if app.pid > 0, let icon = NSRunningApplication(processIdentifier: app.pid)?.icon { return icon }
        let url = app.bundlePath.map { URL(fileURLWithPath: $0) } ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id)
        return url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
struct AudioSnapshot {
    var devices: [AudioDeviceInfo] = []
    var apps: [AudioApplicationInfo] = []
    var output: AudioObjectID = 0
    var input: AudioObjectID = 0
    var outputVolume: Float?
    var inputVolume: Float?
    var inputMuted: Bool?
}
@MainActor protocol AudioBackend: AnyObject {
    func snapshot() -> AudioSnapshot
    func setVolume(_ volume: Float, device: AudioObjectID, input: Bool) throws
    func setDefault(_ device: AudioObjectID, input: Bool) throws
    func setInputMuted(_ muted: Bool, device: AudioObjectID) throws
    func setApplication(_ app: AudioApplicationInfo, gain: Float, output: AudioDeviceInfo) throws
    func retainApplications(_ ids: Set<String>)
    func stopApplications()
}

@MainActor final class AudioController: ObservableObject {
    @Published private(set) var state = AudioSnapshot()
    @Published private(set) var perAppEnabled = false
    @Published private(set) var routedApps: Set<String> = []
    @Published private(set) var gains: [String: Float] = [:]
    @Published private(set) var error: String?
    private let backend: any AudioBackend
    private let defaults: UserDefaults
    private var poll: Task<Void, Never>?
    private var observers = 0
    private var failedApps: Set<String> = []

    init(backend: (any AudioBackend)? = nil, defaults: UserDefaults = .standard) {
        self.backend = backend ?? CoreAudioBackend()
        self.defaults = defaults
        gains = (defaults.dictionary(forKey: "audio.appGains") ?? [:]).compactMapValues { ($0 as? NSNumber)?.floatValue }.mapValues { min(1, max(0, $0)) }
    }
    func refresh() {
        let latest = backend.snapshot()
        if latest.output != state.output { backend.stopApplications(); routedApps = []; failedApps = [] }
        state = latest
        let alive = Set(state.apps.map(\.id))
        backend.retainApplications(alive); routedApps.formIntersection(alive)
        guard perAppEnabled, let output = state.devices.first(where: { $0.id == state.output }) else { return }
        for app in state.apps where gains[app.id] != nil && !failedApps.contains(app.id) {
            do { try backend.setApplication(app, gain: gains[app.id]!, output: output); routedApps.insert(app.id) }
            catch { routedApps.remove(app.id); failedApps.insert(app.id); self.error = error.localizedDescription }
        }
    }
    func observe() {
        observers += 1; refresh()
        guard poll == nil else { return }
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
                if self.observers == 0 && !self.perAppEnabled { self.poll = nil; return }
            }
        }
    }
    func stopObserving() { observers = max(0, observers - 1) }
    func enableApplications() { perAppEnabled = true; failedApps = []; error = nil; refresh() }
    func disableApplications() { backend.stopApplications(); perAppEnabled = false; routedApps = []; failedApps = []; error = nil }
    func setVolume(_ value: Float, input: Bool = false) {
        perform { try backend.setVolume(min(1, max(0, value)), device: input ? state.input : state.output, input: input) }; state = backend.snapshot()
    }
    func selectDevice(_ id: AudioObjectID, input: Bool = false) {
        if !input { backend.stopApplications(); routedApps = []; failedApps = [] }
        perform { try backend.setDefault(id, input: input) }; refresh()
    }
    func muteInput(_ muted: Bool) { perform { try backend.setInputMuted(muted, device: state.input) }; state = backend.snapshot() }
    func setGain(_ value: Float, app: AudioApplicationInfo) {
        guard perAppEnabled, let output = state.devices.first(where: { $0.id == state.output }) else { return }
        let gain = min(1, max(0, value))
        do {
            try backend.setApplication(app, gain: gain, output: output)
            gains[app.id] = gain; routedApps.insert(app.id); failedApps.remove(app.id); error = nil
            defaults.set(gains, forKey: "audio.appGains")
        } catch { routedApps.remove(app.id); self.error = error.localizedDescription }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); error = nil } catch { self.error = error.localizedDescription } }
}

struct AudioFailure: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { "\(operation) failed (\(status)). Playback keeps its normal route. Check the device and macOS audio permission." }
}

// No file, microphone, network or UI work occurs in the real-time callback.
// Handles interleaved and planar Float32 buffers, bounded by their actual sizes.
enum AudioPCM {
    static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, gain: Float, sourceBufferOffset: Int = 0) {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let destination = UnsafeMutableAudioBufferListPointer(output)
        for buffer in destination { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        var sourceChannel = 0
        for index in source.indices where index >= max(0, sourceBufferOffset) {
            let sourceBuffer = source[index]
            guard let sourceData = sourceBuffer.mData?.assumingMemoryBound(to: Float.self), sourceBuffer.mNumberChannels > 0 else { continue }
            let sourceChannels = Int(sourceBuffer.mNumberChannels)
            let sourceFrames = Int(sourceBuffer.mDataByteSize) / MemoryLayout<Float>.size / sourceChannels
            for channel in 0..<sourceChannels {
                var offset = 0
                for target in destination {
                    let channels = Int(target.mNumberChannels)
                    if sourceChannel >= offset && sourceChannel < offset + channels,
                       let targetData = target.mData?.assumingMemoryBound(to: Float.self), channels > 0 {
                        let targetChannel = sourceChannel - offset
                        let frames = min(sourceFrames, Int(target.mDataByteSize) / MemoryLayout<Float>.size / channels)
                        for frame in 0..<frames { targetData[frame * channels + targetChannel] = sourceData[frame * sourceChannels + channel] * min(1, max(0, gain)) }
                        break
                    }
                    offset += channels
                }
                sourceChannel += 1
            }
        }
    }
}

private final class AudioGainState: @unchecked Sendable {
    let gain = OSAllocatedUnfairLock(initialState: Float(1))
    let tapBuffers: Int
    init(tapBuffers: Int = 1) { self.tapBuffers = tapBuffers }
}
private let audioMixerCallback: AudioDeviceIOProc = { _, _, input, _, output, _, context in
    guard let context else { return noErr }
    let state = Unmanaged<AudioGainState>.fromOpaque(context).takeUnretainedValue()
    let count = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).count
    AudioPCM.render(input: input, output: output, gain: state.gain.withLock { $0 }, sourceBufferOffset: max(0, count - state.tapBuffers))
    return noErr
}

private final class ApplicationAudioRoute {
    let processes: [AudioObjectID]
    let output: AudioObjectID
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var callback: AudioDeviceIOProcID?
    private var state = AudioGainState()
    init(app: AudioApplicationInfo, device: AudioDeviceInfo, gain: Float) throws {
        processes = app.processes; output = device.id
        // Device-specific taps avoid sample-rate conversion and encoded audio.
        let description = CATapDescription(processes: app.processes, deviceUID: device.uid, stream: 0)
        description.name = "Sieghart — \(app.name)"; description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        do {
            try check(AudioHardwareCreateProcessTap(description, &tap), "Create app audio tap")
            var format = AudioStreamBasicDescription()
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "Read app audio format")
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mBitsPerChannel == 32, (1...2).contains(format.mChannelsPerFrame), device.outputChannels <= 2 else {
                throw AudioFailure(operation: "This device's audio format is not supported", status: kAudioHardwareUnsupportedOperationError)
            }
            let spec: [String: Any] = [
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceNameKey: "Sieghart private mixer",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceMainSubDeviceKey: device.uid,
                kAudioAggregateDeviceClockDeviceKey: device.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.uid, kAudioSubDeviceInputChannelsKey: 0, kAudioSubDeviceOutputChannelsKey: device.outputChannels]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try check(AudioHardwareCreateAggregateDevice(spec as CFDictionary, &aggregate), "Create private mixer")
            // Aggregate hardware inputs precede the tap. Validate only the
            // tap's stream and disable every hardware input for this IOProc.
            let inputStreams = try streamIDs(scope: kAudioDevicePropertyScopeInput)
            guard let tapStream = inputStreams.last else { throw AudioFailure(operation: "Missing app audio stream", status: kAudioHardwareBadStreamError) }
            var inputFormat = AudioStreamBasicDescription()
            var inputProperty = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyVirtualFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var inputBytes = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tapStream, &inputProperty, 0, nil, &inputBytes, &inputFormat), "Read tap stream format")
            try validate(inputFormat, rate: format.mSampleRate)
            guard inputFormat.mChannelsPerFrame == format.mChannelsPerFrame else { throw AudioFailure(operation: "Tap channel mismatch", status: kAudioHardwareUnsupportedOperationError) }
            state = AudioGainState(tapBuffers: inputFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? Int(inputFormat.mChannelsPerFrame) : 1)
            var outputFormat = AudioStreamBasicDescription()
            var outputProperty = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var outputBytes = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(aggregate, &outputProperty, 0, nil, &outputBytes, &outputFormat), "Read playback format")
            try validate(outputFormat, rate: format.mSampleRate)
            setGain(gain)
            try check(AudioDeviceCreateIOProcID(aggregate, audioMixerCallback, Unmanaged.passUnretained(state).toOpaque(), &callback), "Prepare mixer playback")
            if inputStreams.count > 1 { try disableHardwareInputs(streams: inputStreams.count) }
            try check(AudioDeviceStart(aggregate, callback), "Start mixer playback")
        } catch { close(); throw error }
    }
    func setGain(_ value: Float) { state.gain.withLock { $0 = min(1, max(0, value)) } }
    func close() {
        if let callback { AudioDeviceStop(aggregate, callback); AudioDeviceDestroyIOProcID(aggregate, callback); self.callback = nil }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    deinit { close() }
    private func validate(_ format: AudioStreamBasicDescription, rate: Double) throws {
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate == rate else { throw AudioFailure(operation: "Mixer format mismatch", status: kAudioHardwareUnsupportedOperationError) }
    }
    private func streamIDs(scope: AudioObjectPropertyScope) throws -> [AudioObjectID] {
        var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(aggregate, &property, 0, nil, &size), "Read mixer streams")
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(aggregate, &property, 0, nil, &size, &streams), "Read mixer streams")
        return streams
    }
    private func disableHardwareInputs(streams: Int) throws {
        guard let callback else { return }
        let size = MemoryLayout<AudioHardwareIOProcStreamUsage>.size + (streams - 1) * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let usage = raw.assumingMemoryBound(to: AudioHardwareIOProcStreamUsage.self)
        usage.pointee.mIOProc = unsafeBitCast(callback, to: UnsafeMutableRawPointer.self)
        usage.pointee.mNumberStreams = UInt32(streams)
        let offset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn)!
        let flags = raw.advanced(by: offset).assumingMemoryBound(to: UInt32.self)
        flags[streams - 1] = 1 // Only the final device-specific process tap.
        var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyIOProcStreamUsage, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectSetPropertyData(aggregate, &property, 0, nil, UInt32(size), raw), "Isolate app audio from microphone inputs")
    }
    private func check(_ status: OSStatus, _ action: String) throws { if status != noErr { throw AudioFailure(operation: action, status: status) } }
}

@MainActor final class CoreAudioBackend: AudioBackend {
    private var routes: [String: ApplicationAudioRoute] = [:]
    func snapshot() -> AudioSnapshot {
        let devices = ids(kAudioHardwarePropertyDevices).compactMap { id -> AudioDeviceInfo? in
            // Our aggregate devices are private but can appear in this process's list.
            let uid = string(id, kAudioDevicePropertyDeviceUID)
            guard !uid.isEmpty else { return nil }
            let name = string(id, kAudioObjectPropertyName)
            guard name != "Sieghart private mixer" else { return nil }
            return AudioDeviceInfo(id: id, name: name, uid: uid, inputChannels: channels(id, input: true), outputChannels: channels(id, input: false), transport: scalar(id, kAudioDevicePropertyTransportType) ?? 0)
        }
        let output: UInt32 = scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        let input: UInt32 = scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice) ?? 0
        var grouped: [String: [AudioObjectID]] = [:], owners: [String: NSRunningApplication] = [:], playing: Set<String> = []
        for process in ids(kAudioHardwarePropertyProcessObjectList) {
            let running: UInt32 = scalar(process, kAudioProcessPropertyIsRunningOutput) ?? 0
            let pid: pid_t = scalar(process, kAudioProcessPropertyPID) ?? 0
            guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
                  let app = AudioAppIdentity.owner(of: pid), app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { continue }
            let devices = ids(kAudioProcessPropertyDevices, object: process)
            guard devices.contains(output) || (running == 0 && devices.isEmpty) else { continue }
            let key = app.bundleIdentifier ?? app.bundleURL?.path ?? "process.\(app.processIdentifier)"
            grouped[key, default: []].append(process); owners[key] = app
            if running != 0 { playing.insert(key) }
        }
        let apps = grouped.compactMap { key, processes -> AudioApplicationInfo? in
            guard let owner = owners[key] else { return nil }
            return AudioApplicationInfo(id: key, name: owner.localizedName ?? key, processes: processes.sorted(), pid: owner.processIdentifier, bundlePath: owner.bundleURL?.path, isPlaying: playing.contains(key))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return AudioSnapshot(devices: devices, apps: apps, output: output, input: input, outputVolume: volume(output, input: false), inputVolume: volume(input, input: true), inputMuted: scalar(input, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeInput).map { ( $0 as UInt32 ) != 0 })
    }
    func setVolume(_ volume: Float, device: AudioObjectID, input: Bool) throws {
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        let elements = volumeElements(device, scope: scope)
        guard !elements.isEmpty else { throw AudioFailure(operation: "Device volume is fixed", status: kAudioHardwareUnsupportedOperationError) }
        for element in elements { try write(device, kAudioDevicePropertyVolumeScalar, volume, scope: scope, element: element) }
    }
    func setDefault(_ device: AudioObjectID, input: Bool) throws { try write(AudioObjectID(kAudioObjectSystemObject), input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice, device) }
    func setInputMuted(_ muted: Bool, device: AudioObjectID) throws { try write(device, kAudioDevicePropertyMute, UInt32(muted ? 1 : 0), scope: kAudioDevicePropertyScopeInput) }
    func setApplication(_ app: AudioApplicationInfo, gain: Float, output: AudioDeviceInfo) throws {
        if let existing = routes[app.id], existing.processes == app.processes, existing.output == output.id { existing.setGain(gain); return }
        routes.removeValue(forKey: app.id)?.close()
        routes[app.id] = try ApplicationAudioRoute(app: app, device: output, gain: gain)
    }
    func retainApplications(_ ids: Set<String>) { for id in Array(routes.keys) where !ids.contains(id) { routes.removeValue(forKey: id)?.close() } }
    func stopApplications() { for route in routes.values { route.close() }; routes.removeAll() }
    private func ids(_ selector: AudioObjectPropertySelector, object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject)) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &result) == noErr else { return [] }; return result
    }
    private func scalar<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var size = UInt32(MemoryLayout<T>.size)
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment); defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage) == noErr, size == MemoryLayout<T>.size else { return nil }
        return storage.load(as: T.self)
    }
    private func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String { let value: CFString? = scalar(id, selector); return value.map { $0 as String } ?? "" }
    private func channels(_ id: AudioObjectID, input: Bool) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment); defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    private func volumeElements(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> [AudioObjectPropertyElement] {
        let supported = (0...2).compactMap { element -> AudioObjectPropertyElement? in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: UInt32(element)), writable = DarwinBoolean(false)
            return AudioObjectIsPropertySettable(id, &address, &writable) == noErr && writable.boolValue ? UInt32(element) : nil
        }
        return supported.contains(0) ? [0] : supported
    }
    private func volume(_ id: AudioObjectID, input: Bool) -> Float? {
        let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
        let values: [Float] = volumeElements(id, scope: scope).compactMap { scalar(id, kAudioDevicePropertyVolumeScalar, scope: scope, element: $0) }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }
    private func write<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element), value = value
        let status = withUnsafePointer(to: &value) { AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0) }
        if status != noErr { throw AudioFailure(operation: "Change audio setting", status: status) }
    }
}
