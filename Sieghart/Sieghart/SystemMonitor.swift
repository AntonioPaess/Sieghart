import AppKit
import Combine
import IOKit
import IOKit.ps
import Darwin

struct SystemCounters: Equatable {
    var time: TimeInterval = 0
    var cpu: [UInt64] = [] // user, system, idle, nice
    var received: UInt64 = 0
    var sent: UInt64 = 0
    var diskRead: UInt64 = 0
    var diskWritten: UInt64 = 0
    var diskIOAvailable = false
}
struct MonitorDisk: Identifiable, Equatable {
    var id: String
    var name: String
    var total: Int64
    var free: Int64
}
struct MonitorReading: Equatable {
    var counters = SystemCounters()
    var cpu: Double? = nil
    var gpu: Double? = nil
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var memoryPressure = "Unknown"
    var compressedBytes: UInt64 = 0
    var cachedBytes: UInt64 = 0
    var swapBytes: UInt64? = nil
    var thermalState = "Unknown"
    var localAddresses: [String] = []
    var peripherals: [String] = []
    var batteryCycles: Int? = nil
    var download: Double? = nil
    var upload: Double? = nil
    var diskReadRate: Double? = nil
    var diskWriteRate: Double? = nil
    var disks: [MonitorDisk] = []
    var battery: Double? = nil
    var batteryHealth: Double? = nil
    var watts: Double? = nil
    var onAC = true
    var charging = false
    var batteryMinutes: Int? = nil
    var temperature: Double? = nil
    var fanRPM: Double? = nil
    var sampledAt: Date? = nil
    static func rate(_ value: UInt64, previous: UInt64, seconds: Double) -> Double? {
        guard seconds > 0, value >= previous else { return nil }
        return Double(value - previous) / seconds
    }
    mutating func derive(from previous: SystemCounters?) {
        guard let previous else { return }
        let dt = counters.time - previous.time
        guard dt > 0 else { return }
        if counters.cpu.count == 4, previous.cpu.count == 4, zip(counters.cpu, previous.cpu).allSatisfy({ $0 >= $1 }) {
            let deltas = zip(counters.cpu, previous.cpu).map { $0 - $1 }
            let total = deltas.reduce(UInt64(0), +)
            if total > 0 { cpu = Double(total - deltas[2]) / Double(total) }
        }
        download = Self.rate(counters.received, previous: previous.received, seconds: dt)
        upload = Self.rate(counters.sent, previous: previous.sent, seconds: dt)
        if counters.diskIOAvailable && previous.diskIOAvailable {
            diskReadRate = Self.rate(counters.diskRead, previous: previous.diskRead, seconds: dt)
            diskWriteRate = Self.rate(counters.diskWritten, previous: previous.diskWritten, seconds: dt)
        }
    }
}
@MainActor protocol SystemSampling: AnyObject { func read() -> MonitorReading }
@MainActor final class SystemMonitor: ObservableObject {
    @Published private(set) var reading = MonitorReading()
    @Published private(set) var history: [MonitorReading] = []
    let backend: any SystemSampling
    private var task: Task<Void, Never>?
    private var observers = 0
    var onReading: ((MonitorReading) -> Void)?
    init(backend: (any SystemSampling)? = nil) { self.backend = backend ?? MacSystemSampler() }
    func refresh() {
        var next = backend.read()
        next.derive(from: reading.sampledAt == nil ? nil : reading.counters)
        reading = next
        history.append(next); history = Array(history.suffix(60))
        onReading?(next)
    }
    func observe() {
        observers += 1; refresh()
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }
    func stopObserving() {
        observers = max(0, observers - 1)
        if observers == 0 { task?.cancel(); task = nil }
    }
}

@MainActor final class MacSystemSampler: SystemSampling {
    func read() -> MonitorReading {
        var result = MonitorReading()
        result.sampledAt = Date(); result.counters.time = ProcessInfo.processInfo.systemUptime
        result.memoryTotal = ProcessInfo.processInfo.physicalMemory
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: result.thermalState = "Normal"
        case .fair: result.thermalState = "Warm"
        case .serious: result.thermalState = "High"
        case .critical: result.thermalState = "Critical"
        @unknown default: break
        }
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = host_cpu_load_info(), cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let cpuStatus = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount) }
        }
        if cpuStatus == KERN_SUCCESS { result.counters.cpu = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3].map(UInt64.init) }
        var vm = vm_statistics64(), vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmStatus = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { host_statistics64(host, HOST_VM_INFO64, $0, &vmCount) }
        }
        var page: vm_size_t = 0; host_page_size(host, &page)
        if vmStatus == KERN_SUCCESS {
            // App pages + wired + compressor. File cache and purgeable pages
            // are reclaimable, so they aren't presented as application memory.
            let appPages = max(Int64(0), Int64(vm.active_count) + Int64(vm.inactive_count) - Int64(vm.external_page_count) - Int64(vm.purgeable_count))
            result.memoryUsed = min(result.memoryTotal, (UInt64(appPages) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)) * UInt64(page))
            result.compressedBytes = UInt64(vm.compressor_page_count) * UInt64(page)
            result.cachedBytes = UInt64(vm.external_page_count) * UInt64(page)
        }
        var swap = xsw_usage(), swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 { result.swapBytes = swap.xsu_used }
        var pressure: Int32 = 0, pressureSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0 {
            result.memoryPressure = pressure == 1 ? "Normal" : pressure == 2 ? "Warning" : pressure == 4 ? "Critical" : "Unknown"
        }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&interfaces) == 0 {
            defer { freeifaddrs(interfaces) }
            var cursor = interfaces
            while let interface = cursor {
                defer { cursor = interface.pointee.ifa_next }
                if let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), String(cString: interface.pointee.ifa_name).hasPrefix("en") {
                    var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(address, socklen_t(address.pointee.sa_len), &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 {
                        result.localAddresses.append(String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
                    }
                }
                guard let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                      interface.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                      let data = interface.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
                // Physical Ethernet/Wi-Fi interfaces exclude VPN overlays to
                // avoid counting the same packet twice.
                let name = String(cString: interface.pointee.ifa_name)
                guard name.hasPrefix("en") else { continue }
                result.counters.received += UInt64(data.pointee.ifi_ibytes)
                result.counters.sent += UInt64(data.pointee.ifi_obytes)
            }
        }
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey], options: [.skipHiddenVolumes]) ?? []
        result.disks = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
                  let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage, total > 0 else { return nil }
            return MonitorDisk(id: url.path, name: values.volumeName ?? url.lastPathComponent, total: Int64(total), free: max(0, min(Int64(total), free)))
        }
        if !result.disks.contains(where: { $0.id == "/" }), let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]), let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage {
            result.disks.insert(MonitorDisk(id: "/", name: values.volumeName ?? "Mac", total: Int64(total), free: free), at: 0)
        }
        Self.properties(className: "IOBlockStorageDriver").forEach { properties in
            if let stats = properties["Statistics"] as? [String: Any],
               let read = stats["Bytes (Read)"] as? NSNumber,
               let written = stats["Bytes (Write)"] as? NSNumber {
                result.counters.diskIOAvailable = true
                result.counters.diskRead += read.uint64Value
                result.counters.diskWritten += written.uint64Value
            }
        }
        let gpu = Self.properties(className: "IOAccelerator").compactMap { ($0["PerformanceStatistics"] as? [String: Any])?["Device Utilization %"] as? NSNumber }.map(\.doubleValue)
        if let maximum = gpu.max() { result.gpu = min(1, max(0, maximum / 100)) }
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      let current = data[kIOPSCurrentCapacityKey] as? NSNumber, let maximum = data[kIOPSMaxCapacityKey] as? NSNumber, maximum.doubleValue > 0 else { continue }
                result.battery = min(1, max(0, current.doubleValue / maximum.doubleValue))
                result.onAC = data[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                result.charging = data[kIOPSIsChargingKey] as? Bool ?? false
                let minutes = (data[result.charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
                result.batteryMinutes = minutes.flatMap { $0 > 0 ? $0 : nil }
                break
            }
        }
        if let battery = Self.properties(className: "AppleSmartBattery").first {
            result.batteryCycles = (battery["CycleCount"] as? NSNumber)?.intValue
            if let current = battery["AppleRawMaxCapacity"] as? NSNumber, let design = battery["DesignCapacity"] as? NSNumber, design.doubleValue > 0 { result.batteryHealth = min(1, current.doubleValue / design.doubleValue) }
            if let amperage = battery["Amperage"] as? NSNumber, let voltage = battery["Voltage"] as? NSNumber {
                // Signed current; report magnitude, with charging separately.
                result.watts = abs(Double(amperage.int32Value) * voltage.doubleValue / 1_000_000)
            }
        }
        result.peripherals = Array(Set(Self.properties(className: "IOUSBHostDevice").compactMap { $0["USB Product Name"] as? String })).sorted()
        return result
    }
    static func properties(className: String) -> [[String: Any]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [[String: Any]] = []
        while true {
            let service = IOIteratorNext(iterator); guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dictionary = properties?.takeRetainedValue() as? [String: Any] { result.append(dictionary) }
        }
        return result
    }
}
