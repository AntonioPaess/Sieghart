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
    var sampleRate: Double = 0
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

// Responsibility metadata covers XPC audio helpers whose parent is launchd.
// It is optional and Mac-only; ancestry/bundle/path lookup remains the fallback.
enum AudioAppIdentity {
    private static let responsibilityLookup: (@convention(c) (pid_t) -> pid_t)? = {
        #if SIEGHART_CHALLENGE
        return nil
        #else
        guard let handle = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let function = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(function, to: (@convention(c) (pid_t) -> pid_t).self)
        #endif
    }()

    static func ancestor(of pid: pid_t, isApplication: (pid_t) -> Bool, parent: (pid_t) -> pid_t) -> pid_t? {
        var current = pid, visited: Set<pid_t> = []
        for _ in 0..<32 {
            guard current > 1, visited.insert(current).inserted else { return nil }
            if isApplication(current) { return current }
            current = parent(current)
        }
        return nil
    }
    static func applicationPID(of pid: pid_t, isApplication: (pid_t) -> Bool,
                               parent: (pid_t) -> pid_t, responsible: (pid_t) -> pid_t?) -> pid_t? {
        guard pid > 1 else { return nil }
        if isApplication(pid) { return pid }
        if let owner = responsible(pid), owner > 1, owner != pid,
           let app = ancestor(of: owner, isApplication: isApplication, parent: parent) { return app }
        return ancestor(of: pid, isApplication: isApplication, parent: parent)
    }
    @MainActor static func owner(of pid: pid_t, bundleID: String = "") -> NSRunningApplication? {
        if let id = applicationPID(of: pid, isApplication: { NSRunningApplication(processIdentifier: $0)?.activationPolicy == .regular }, parent: { id in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            return proc_pidinfo(id, PROC_PIDTBSDINFO, 0, &info, size) == size ? pid_t(info.pbi_ppid) : 0
        }, responsible: { responsibilityLookup?($0) }) { return NSRunningApplication(processIdentifier: id) }
        if !bundleID.isEmpty, let app = NSWorkspace.shared.runningApplications.filter({ app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
            return bundleID == id || bundleID.hasPrefix(id + ".")
        }).max(by: { ($0.bundleIdentifier?.count ?? 0) < ($1.bundleIdentifier?.count ?? 0) }) { return app }
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
enum AudioMixerApps {
    // Finder remains available through Master/system sound, not a mixer tower.
    static func isEligible(_ id: String) -> Bool { id != "com.apple.finder" }
}
struct HiddenAudioApplication: Identifiable, Equatable {
    let id: String
    let name: String
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
    func prepareApplicationAudio() async throws
    func setVolume(_ volume: Float, device: AudioObjectID, input: Bool) throws
    func setDefault(_ device: AudioObjectID, input: Bool) throws
    func setInputMuted(_ muted: Bool, device: AudioObjectID) throws
    func setApplication(_ app: AudioApplicationInfo, gain: Float, output: AudioDeviceInfo) throws
    func retainApplications(_ ids: Set<String>)
    func stopApplications()
}

enum AppMixerAccess: Equatable { case off, requesting, ready, permissionRequired, failed }

struct AudioFailure: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? {
        if status == kAudioDevicePermissionsError { return "Allow Sieghart in System Settings → Privacy & Security → Screen & System Audio Recording, then retry the app mixer." }
        return "\(operation) failed (\(status)). Check the selected audio device and retry."
    }
}

// No file, microphone, network or UI work occurs in the real-time callback.
// Handles interleaved and planar Float32 buffers, bounded by their actual sizes.
enum AudioPCM {
    static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, gain: Float, sourceBufferOffset: Int = 0) {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let destination = UnsafeMutableAudioBufferListPointer(output)
        for buffer in destination { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        let offset = max(0, sourceBufferOffset)
        guard offset < source.count else { return }
        var inputChannels = 0
        for index in source.indices where index >= offset { inputChannels += Int(source[index].mNumberChannels) }
        let outputChannels = destination.reduce(0) { $0 + Int($1.mNumberChannels) }
        guard inputChannels > 0, outputChannels > 0 else { return }
        var targetChannelBase = 0
        for buffer in destination {
            let channels = Int(buffer.mNumberChannels)
            defer { targetChannelBase += channels }
            guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let outputFrames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            var sourceChannelBase = 0
            for index in source.indices where index >= offset {
                let incoming = source[index], count = Int(incoming.mNumberChannels)
                defer { sourceChannelBase += count }
                guard count > 0, let samples = incoming.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let frames = min(outputFrames, Int(incoming.mDataByteSize) / MemoryLayout<Float>.size / count)
                for channel in 0..<count {
                    let number = sourceChannelBase + channel
                    for outputChannel in 0..<channels {
                        let target = targetChannelBase + outputChannel
                        // Stereo calls fold into a mono headset; mono fills
                        // both front speakers. Additional device channels stay silent.
                        let foldsToMono = outputChannels == 1 && inputChannels > 1
                        if foldsToMono || target == number || (inputChannels == 1 && target == 1) {
                            let level = min(1, max(0, gain)) / (foldsToMono ? Float(inputChannels) : 1)
                            for frame in 0..<frames { data[frame * channels + outputChannel] += samples[frame * count + channel] * level }
                        }
                    }
                }
            }
        }
    }
}

private final class AudioGainState: @unchecked Sendable {
    let gain = OSAllocatedUnfairLock(initialState: Float(1))
    let tapBuffers: Int
    let tapChannels: Int
    init(tapBuffers: Int = 1, tapChannels: Int = 2) { self.tapBuffers = tapBuffers; self.tapChannels = tapChannels }
}
private let audioMixerCallback: AudioDeviceIOProc = { _, _, input, _, output, _, context in
    guard let context else { return noErr }
    let state = Unmanaged<AudioGainState>.fromOpaque(context).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
    // If the tap is absent, do not fall back to a hardware microphone buffer.
    guard buffers.count >= state.tapBuffers,
          (state.tapBuffers > 1 || Int(buffers[buffers.count - 1].mNumberChannels) == state.tapChannels) else {
        for buffer in UnsafeMutableAudioBufferListPointer(output) { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
        return noErr
    }
    AudioPCM.render(input: input, output: output, gain: state.gain.withLock { $0 }, sourceBufferOffset: buffers.count - state.tapBuffers)
    return noErr
}

// Starting an aggregate with a tap invokes the public macOS permission path.
// An empty inclusion list captures no app audio; the unmuted probe has no
// physical input/output subdevice and never changes another app's playback.
private enum SystemAudioPermissionProbe {
    static func run() throws {
        guard let purpose = Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") as? String, !purpose.isEmpty else {
            throw AudioFailure(operation: "System audio permission description is missing", status: kAudioHardwareIllegalOperationError)
        }
        // An empty inclusion list taps no processes and can skip the privacy
        // request. A temporary unmuted global tap exercises the capture path.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "Sieghart audio access"; description.isPrivate = true; description.muteBehavior = .unmuted
        var tap: AudioObjectID = 0, device: AudioObjectID = 0
        var io: AudioDeviceIOProcID?
        defer {
            if let io { AudioDeviceStop(device, io); AudioDeviceDestroyIOProcID(device, io) }
            if device != 0 { AudioHardwareDestroyAggregateDevice(device) }
            if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
        }
        try audioCheck(AudioHardwareCreateProcessTap(description, &tap), "Prepare system audio access")
        let spec: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sieghart audio access",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
            kAudioAggregateDeviceTapAutoStartKey: true
        ]
        try audioCheck(AudioHardwareCreateAggregateDevice(spec as CFDictionary, &device), "Prepare system audio permission")
        try audioCheck(AudioDeviceCreateIOProcID(device, { _, _, _, _, output, _, _ in
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }, nil, &io), "Prepare audio permission request")
        try audioCheck(AudioDeviceStart(device, io), "Request system audio permission")
    }
}
private func audioCheck(_ status: OSStatus, _ operation: String) throws {
    if status != noErr { throw AudioFailure(operation: operation, status: status) }
}

private final class ApplicationAudioRoute {
    let processes: [AudioObjectID]
    let output: AudioObjectID
    let device: AudioDeviceInfo
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var callback: AudioDeviceIOProcID?
    private var state = AudioGainState()
    init(app: AudioApplicationInfo, device: AudioDeviceInfo, gain: Float) throws {
        processes = app.processes; output = device.id; self.device = device
        // A stereo process mix includes all of an app's output streams, also
        // when a call changes a Bluetooth headset's stream/rate/channel layout.
        let description = CATapDescription(stereoMixdownOfProcesses: app.processes)
        description.name = "Sieghart — \(app.name)"; description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        do {
            try audioCheck(AudioHardwareCreateProcessTap(description, &tap), "Create app audio tap")
            let format = try readFormat(of: tap, selector: kAudioTapPropertyFormat)
            try validatePCM(format)
            let spec: [String: Any] = [
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceNameKey: "Sieghart private mixer",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: device.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: device.uid, kAudioSubDeviceInputChannelsKey: 0]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try audioCheck(AudioHardwareCreateAggregateDevice(spec as CFDictionary, &aggregate), "Create private mixer")
            let playback = try readFormat(of: aggregate, selector: kAudioDevicePropertyStreamFormat, scope: kAudioDevicePropertyScopeOutput)
            try validatePCM(playback)
            // HAL performs the tap/device clock conversion. Equality of nominal
            // rates is not required and changes during AirPods calls are normal.
            state = AudioGainState(tapBuffers: format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? Int(format.mChannelsPerFrame) : 1, tapChannels: Int(format.mChannelsPerFrame))
            setGain(gain)
            try audioCheck(AudioDeviceCreateIOProcID(aggregate, audioMixerCallback, Unmanaged.passUnretained(state).toOpaque(), &callback), "Prepare mixer playback")
            try audioCheck(AudioDeviceStart(aggregate, callback), "Start mixer playback")
        } catch { close(); throw error }
    }
    func setGain(_ value: Float) { state.gain.withLock { $0 = min(1, max(0, value)) } }
    func close() {
        if let callback { AudioDeviceStop(aggregate, callback); AudioDeviceDestroyIOProcID(aggregate, callback); self.callback = nil }
        if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate); aggregate = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    deinit { close() }
    private func validatePCM(_ format: AudioStreamBasicDescription) throws {
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mChannelsPerFrame > 0 else {
            throw AudioFailure(operation: "This device's audio format is not supported", status: kAudioDeviceUnsupportedFormatError)
        }
    }
    private func readFormat(of object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> AudioStreamBasicDescription {
        var property = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription(), size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try audioCheck(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &format), "Read mixer audio format")
        return format
    }
}

@MainActor final class CoreAudioBackend: AudioBackend {
    private var routes: [String: ApplicationAudioRoute] = [:]
    func prepareApplicationAudio() async throws {
        try await Task.detached(priority: .userInitiated) { try SystemAudioPermissionProbe.run() }.value
    }
    func snapshot() -> AudioSnapshot {
        let devices = ids(kAudioHardwarePropertyDevices).compactMap { id -> AudioDeviceInfo? in
            // Our aggregate devices are private but can appear in this process's list.
            let uid = string(id, kAudioDevicePropertyDeviceUID)
            guard !uid.isEmpty else { return nil }
            let name = string(id, kAudioObjectPropertyName)
            guard name != "Sieghart private mixer", name != "Sieghart audio access" else { return nil }
            return AudioDeviceInfo(id: id, name: name, uid: uid, inputChannels: channels(id, input: true), outputChannels: channels(id, input: false), transport: scalar(id, kAudioDevicePropertyTransportType) ?? 0, sampleRate: scalar(id, kAudioDevicePropertyNominalSampleRate) ?? 0)
        }
        let output: UInt32 = scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        let input: UInt32 = scalar(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice) ?? 0
        var grouped: [String: [AudioObjectID]] = [:], owners: [String: NSRunningApplication] = [:], playing: Set<String> = []
        // All visible running apps stay discoverable. Apps without an audio
        // connection are listed as waiting, never given an ineffective tap.
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            let key = app.bundleIdentifier ?? app.bundleURL?.path ?? "process.\(app.processIdentifier)"
            guard AudioMixerApps.isEligible(key) else { continue }
            owners[key] = app; grouped[key] = []
        }
        for process in ids(kAudioHardwarePropertyProcessObjectList) {
            let running: UInt32 = scalar(process, kAudioProcessPropertyIsRunningOutput) ?? 0
            let pid: pid_t = scalar(process, kAudioProcessPropertyPID) ?? 0
            guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier,
                  let app = AudioAppIdentity.owner(of: pid, bundleID: string(process, kAudioProcessPropertyBundleID)), app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { continue }
            let key = app.bundleIdentifier ?? app.bundleURL?.path ?? "process.\(app.processIdentifier)"
            guard AudioMixerApps.isEligible(key) else { continue }
            grouped[key, default: []].append(process); owners[key] = app
            if running != 0 { playing.insert(key) }
        }
        let apps = grouped.compactMap { key, processes -> AudioApplicationInfo? in
            guard let owner = owners[key] else { return nil }
            return AudioApplicationInfo(id: key, name: owner.localizedName ?? key, processes: processes.sorted(), pid: owner.processIdentifier, bundlePath: owner.bundleURL?.path, isPlaying: playing.contains(key))
        }.sorted {
            if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
            if $0.processes.isEmpty != $1.processes.isEmpty { return !$0.processes.isEmpty }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
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
        // Unity is passthrough; no tap is needed to play at normal volume.
        if gain >= 1 { routes.removeValue(forKey: app.id)?.close(); return }
        if let existing = routes[app.id], existing.processes == app.processes, existing.device == output { existing.setGain(gain); return }
        let replacement = try ApplicationAudioRoute(app: app, device: output, gain: gain)
        routes.removeValue(forKey: app.id)?.close()
        routes[app.id] = replacement
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
