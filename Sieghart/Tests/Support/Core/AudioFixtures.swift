import CoreAudio
import Foundation

@MainActor final class CoreMockAudio: AudioBackend {
  var reading = AudioSnapshot(
    devices: [
      AudioDeviceInfo(id: 1, name: "Output", uid: "out", inputChannels: 0, outputChannels: 2),
      AudioDeviceInfo(id: 2, name: "Input", uid: "in", inputChannels: 1, outputChannels: 0),
      AudioDeviceInfo(id: 3, name: "Headphones", uid: "other", inputChannels: 0, outputChannels: 2),
    ], apps: [AudioApplicationInfo(id: "test.app", name: "Player", processes: [11], pid: 99)],
    output: 1, input: 2, outputVolume: 0.5, inputVolume: 0.8, inputMuted: false)
  var routes: [String: Float] = [:]
  var appliedProcesses: [String: [AudioObjectID]] = [:]
  var stopped = 0
  var fail = false
  var calls = 0
  var permissionRequests = 0
  var permissionFailure: OSStatus?
  var pending: CheckedContinuation<Void, Never>?
  var holdsRequest = false
  var permissionStarted: (() -> Void)?
  func prepareApplicationAudio() async throws {
    permissionRequests += 1
    if holdsRequest {
      await withCheckedContinuation {
        pending = $0
        permissionStarted?()
      }
    }
    if let status = permissionFailure {
      throw AudioFailure(operation: "Permission fixture", status: status)
    }
  }
  func snapshot() -> AudioSnapshot { reading }
  func setVolume(_ value: Float, device: AudioObjectID, input: Bool) throws {
    if input { reading.inputVolume = value } else { reading.outputVolume = value }
  }
  func setDefault(_ device: AudioObjectID, input: Bool) throws {
    if fail { throw AudioFailure(operation: "Fixture", status: -1) }
    if input { reading.input = device } else { reading.output = device }
  }
  func setInputMuted(_ muted: Bool, device: AudioObjectID) throws { reading.inputMuted = muted }
  func setApplication(_ app: AudioApplicationInfo, gain: Float, output: AudioDeviceInfo) throws {
    calls += 1
    if fail { throw AudioFailure(operation: "Fixture", status: -1) }
    routes[app.id] = gain
    appliedProcesses[app.id] = app.processes
  }
  func retainApplications(_ ids: Set<String>) { routes = routes.filter { ids.contains($0.key) } }
  func stopApplications() {
    stopped += 1
    routes = [:]
  }
}
final class CoreBuffers {
  let list: UnsafeMutableAudioBufferListPointer
  let samples: [UnsafeMutablePointer<Float>]
  init(_ contents: [[Float]], channels: [UInt32]) {
    let storage = UnsafeMutableRawPointer.allocate(
      byteCount: MemoryLayout<AudioBufferList>.size + (contents.count - 1)
        * MemoryLayout<AudioBuffer>.stride,
      alignment: MemoryLayout<AudioBufferList>.alignment)
    let pointer = storage.assumingMemoryBound(to: AudioBufferList.self)
    pointer.pointee.mNumberBuffers = UInt32(contents.count)
    list = UnsafeMutableAudioBufferListPointer(pointer)
    samples = contents.map { values in
      let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, values.count))
      pointer.initialize(from: values, count: values.count)
      return pointer
    }
    for index in contents.indices {
      list[index] = AudioBuffer(
        mNumberChannels: channels[index], mDataByteSize: UInt32(contents[index].count * 4),
        mData: samples[index])
    }
  }
  func values(_ index: Int, count: Int) -> [Float] {
    Array(UnsafeBufferPointer(start: samples[index], count: count))
  }
  deinit {
    for sample in samples { sample.deallocate() }
    list.unsafeMutablePointer.deallocate()
  }
}
