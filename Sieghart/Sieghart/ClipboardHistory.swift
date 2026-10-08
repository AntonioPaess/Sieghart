import AppKit
import ApplicationServices
import CryptoKit
import Foundation
import Combine
import IOKit
import Darwin

// Native clipboard data stays local. File entries store references, never file contents.
enum ClipboardCleanup: String, CaseIterable, Identifiable {
    case afterDays = "After a number of days", shutdown = "When the Mac shuts down", lidClose = "When the lid closes"
    var id: String { rawValue }
}
enum ClipboardKind: String, Codable, CaseIterable, Sendable { case text, image, files }
struct ClipboardPayload: Codable, Equatable, Sendable {
    var kind: ClipboardKind
    var text: String = ""
    var image: Data = Data()
    var files: [URL] = []
    var byteCount: Int { text.utf8.count + image.count + files.reduce(0) { $0 + $1.absoluteString.utf8.count } }
    var title: String {
        switch kind {
        case .text: return String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(140) ?? "".prefix(140))
        case .image: return "Copied image"
        case .files: return files.count == 1 ? files[0].lastPathComponent : "\(files.count) files"
        }
    }
    var valid: Bool {
        switch kind {
        case .text: return !text.isEmpty && text.utf8.count <= 512 * 1024 && image.isEmpty && files.isEmpty
        case .image: return !image.isEmpty && image.count <= 8 * 1024 * 1024 && text.isEmpty && files.isEmpty && image.starts(with: [137,80,78,71,13,10,26,10])
        case .files: return !files.isEmpty && files.count <= 50 && files.allSatisfy { $0.isFileURL && $0.absoluteString.utf8.count <= 8192 } && text.isEmpty && image.isEmpty
        }
    }
    var fingerprint: String {
        var data = Data(kind.rawValue.utf8)
        data.append(Data(text.utf8)); data.append(image)
        for url in files { data.append(0); data.append(Data(url.absoluteString.utf8)) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
struct ClipboardEntry: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var payload: ClipboardPayload
    var copiedAt = Date()
    var sourceName: String
    var sourceBundle: String
    var pinned = false
}
struct ClipboardRead: Sendable {
    var changeCount: Int
    var payload: ClipboardPayload?
}

@MainActor protocol ClipboardAccess: AnyObject {
    func read(after changeCount: Int?, includeMedia: Bool) async -> ClipboardRead?
    func write(_ payload: ClipboardPayload) async -> Int?
}
protocol ClipboardStorage: Sendable {
    func load() async throws -> [ClipboardEntry]
    func save(_ entries: [ClipboardEntry], revision: UInt64) async throws
}
actor LocalClipboardStorage: ClipboardStorage {
    private let url: URL
    private var lastRevision: UInt64 = 0
    init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sieghart/Clipboard/history.json")) { self.url = url }
    func load() throws -> [ClipboardEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= 60 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: url))
    }
    func save(_ entries: [ClipboardEntry], revision: UInt64) throws {
        guard revision >= lastRevision else { return }
        let data = try JSONEncoder().encode(entries)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        lastRevision = revision
    }
}

// A slow promised pasteboard provider cannot block the main thread or queue
// unlimited reads. A timeout discards its result; the worker remains reserved
// until the original operation actually returns.
private final class PasteboardWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sieghart.clipboard", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    func run<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T? {
        guard lock.withLock({ if busy { return false }; busy = true; return true }) else { return nil }
        return await withCheckedContinuation { continuation in
            let delivery = PasteboardDelivery<T>(continuation)
            queue.async { [self] in
                let result = body()
                lock.withLock { busy = false }
                delivery.finish(result)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { delivery.finish(nil) }
        }
    }
}
private final class PasteboardDelivery<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?
    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }
    func finish(_ value: T?) {
        let pending = lock.withLock { let pending = continuation; continuation = nil; return pending }
        pending?.resume(returning: value)
    }
}
@MainActor final class SystemClipboardAccess: ClipboardAccess {
    private let worker = PasteboardWorker()
    nonisolated static let excludedTypes: Set<String> = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
    func read(after changeCount: Int?, includeMedia: Bool) async -> ClipboardRead? {
        await worker.run {
            let board = NSPasteboard.general, count = board.changeCount
            // Baseline only: enabling/resuming does not capture an earlier copy.
            guard let changeCount, count != changeCount else { return ClipboardRead(changeCount: count, payload: nil) }
            let types = Set((board.types ?? []).map(\.rawValue))
            guard types.isDisjoint(with: Self.excludedTypes) else { return ClipboardRead(changeCount: count, payload: nil) }
            var payload: ClipboardPayload?
            if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
                if includeMedia, let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], urls.count <= 50 {
                    payload = ClipboardPayload(kind: .files, files: urls)
                }
            } else if includeMedia && (types.contains(NSPasteboard.PasteboardType.png.rawValue) || types.contains(NSPasteboard.PasteboardType.tiff.rawValue)) {
                let raw = board.data(forType: .png) ?? board.data(forType: .tiff)
                if let raw, raw.count <= 8 * 1024 * 1024, let bitmap = NSBitmapImageRep(data: raw), bitmap.pixelsWide <= 8192, bitmap.pixelsHigh <= 8192,
                   let png = bitmap.representation(using: .png, properties: [:]), png.count <= 8 * 1024 * 1024 {
                    payload = ClipboardPayload(kind: .image, image: png)
                }
            } else if let text = board.string(forType: .string), text.utf8.count <= 512 * 1024 { payload = ClipboardPayload(kind: .text, text: text) }
            guard board.changeCount == count else { return ClipboardRead(changeCount: count, payload: nil) }
            return ClipboardRead(changeCount: count, payload: payload?.valid == true ? payload : nil)
        }
    }
    func write(_ payload: ClipboardPayload) async -> Int? {
        guard payload.valid else { return nil }
        return await worker.run {
            let board = NSPasteboard.general
            board.clearContents()
            let success: Bool
            switch payload.kind {
            case .text: success = board.setString(payload.text, forType: .string)
            case .image: success = board.setData(payload.image, forType: .png)
            case .files: success = board.writeObjects(payload.files.map { $0 as NSURL })
            }
            return success ? board.changeCount : -1
        }.flatMap { $0 >= 0 ? $0 : nil }
    }
}

@MainActor final class ClipboardController: ObservableObject {
    static let maxEntries = 200
    static let maxBytes = 40 * 1024 * 1024
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var status = "History is off"
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: "clipboard.enabled"); resetCapture() } }
    @Published var isPaused = false { didSet { resetCapture() } }
    @Published var includeMedia: Bool { didSet { defaults.set(includeMedia, forKey: "clipboard.media"); resetCapture() } }
    @Published var excludedApps: String { didSet { defaults.set(excludedApps, forKey: "clipboard.excludedApps"); resetCapture() } }
    @Published var historyLimit: Int { didSet {
        if ![5, 10, 20].contains(historyLimit) { historyLimit = 20; return }
        defaults.set(historyLimit, forKey: "clipboard.limit"); prune()
    } }
    @Published var cleanup: ClipboardCleanup { didSet {
        defaults.set(cleanup.rawValue, forKey: "clipboard.cleanup")
        defaults.set(bootTime(), forKey: "clipboard.boot"); prune()
    } }
    @Published var retentionDays: Int { didSet {
        if !(1...365).contains(retentionDays) { retentionDays = min(365, max(1, retentionDays)); return }
        defaults.set(retentionDays, forKey: "clipboard.days"); prune()
    } }
    @Published private(set) var loaded = false
    private let defaults: UserDefaults
    private let access: any ClipboardAccess
    private let storage: any ClipboardStorage
    private let now: () -> Date
    private var generation = 0
    private var lastCount: Int?
    private var reading = false
    private var copying = false
    private var revision: UInt64 = 0
    private var polling: Task<Void, Never>?
    private var persistence: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var sessionSuspended = false
    private var excludedSinceRead = false
    private(set) var pasteTarget: NSRunningApplication?
    private let monitorsSystem: Bool
    private let bootTime: () -> TimeInterval
    private var lidWasClosed = false
    private var lastPrune = Date.distantPast
    init(defaults: UserDefaults = .standard, access: (any ClipboardAccess)? = nil, storage: any ClipboardStorage = LocalClipboardStorage(), monitorsSystem: Bool = true, now: @escaping () -> Date = Date.init, bootTime: @escaping () -> TimeInterval = ClipboardController.systemBootTime) {
        self.defaults = defaults; self.access = access ?? SystemClipboardAccess(); self.storage = storage; self.monitorsSystem = monitorsSystem; self.now = now; self.bootTime = bootTime
        let limit = defaults.integer(forKey: "clipboard.limit")
        historyLimit = [5, 10, 20].contains(limit) ? limit : 20
        cleanup = defaults.string(forKey: "clipboard.cleanup").flatMap(ClipboardCleanup.init(rawValue:)) ?? .afterDays
        let days = defaults.integer(forKey: "clipboard.days"); retentionDays = days > 0 ? min(365, days) : 30
        isEnabled = defaults.bool(forKey: "clipboard.enabled")
        includeMedia = defaults.object(forKey: "clipboard.media") == nil ? true : defaults.bool(forKey: "clipboard.media")
        excludedApps = defaults.string(forKey: "clipboard.excludedApps") ?? "com.1password.1password\ncom.agilebits.onepassword7\ncom.bitwarden.desktop\ncom.apple.Passwords"
    }
    func start() {
        guard polling == nil else { return }
        if monitorsSystem { observeSession() }
        polling = Task { @MainActor [weak self] in
            await self?.restore()
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
    func restore() async {
        guard !loaded else { return }
        do {
            let saved = try await storage.load()
            let previousBoot = defaults.double(forKey: "clipboard.boot"), currentBoot = bootTime()
            let rebooted = cleanup == .shutdown && previousBoot > 0 && abs(previousBoot - currentBoot) > 10
            entries = rebooted ? [] : bounded(saved)
            defaults.set(currentBoot, forKey: "clipboard.boot")
            if entries != saved { save() }
            loaded = true; status = isEnabled ? "Ready for your next copy" : "History is off"
        } catch { loaded = true; isEnabled = false; status = "Saved history could not be read. Review the file before enabling history." }
    }
    private func resetCapture() {
        generation += 1; lastCount = nil
        status = !isEnabled ? "History is off" : isPaused ? "History paused" : "Ready for your next copy"
    }
    func poll(sourceName: String? = nil, sourceBundle: String? = nil) async {
        if monitorsSystem { checkLid() }
        if loaded && now().timeIntervalSince(lastPrune) >= 60 { prune(); lastPrune = now() }
        guard loaded, isEnabled, !isPaused, !sessionSuspended, !reading, !copying else { return }
        reading = true; defer { reading = false }
        let current = generation
        let name = sourceName ?? NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app"
        let bundle = sourceBundle ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let ignored = isExcluded(bundle) || excludedSinceRead
        excludedSinceRead = false
        guard let snapshot = await access.read(after: lastCount, includeMedia: includeMedia), current == generation, isEnabled, !isPaused, !sessionSuspended else { return }
        let baseline = lastCount == nil; lastCount = snapshot.changeCount
        guard !baseline, !ignored, !excludedSinceRead, let payload = snapshot.payload else { return }
        record(payload, sourceName: name, sourceBundle: bundle)
    }
    func record(_ payload: ClipboardPayload, sourceName: String, sourceBundle: String) {
        guard isEnabled, !isPaused, payload.valid, !isExcluded(sourceBundle), includeMedia || payload.kind == .text else { return }
        let digest = payload.fingerprint
        var next = entries
        if let index = next.firstIndex(where: { $0.payload.fingerprint == digest }) {
            var entry = next.remove(at: index); entry.copiedAt = now(); entry.sourceName = sourceName; entry.sourceBundle = sourceBundle
            next.insert(entry, at: 0)
        } else { next.insert(ClipboardEntry(payload: payload, copiedAt: now(), sourceName: sourceName, sourceBundle: sourceBundle), at: 0) }
        entries = bounded(next)
        guard entries.contains(where: { $0.payload.fingerprint == digest }) else { status = "History is full. Unpin or delete a copy to make room."; return }
        status = "Saved locally"; save()
    }
    static func bounded(_ items: [ClipboardEntry], now: Date, limit: Int = maxEntries, retentionDays: Int? = 30) -> [ClipboardEntry] {
        var unique = Set<String>(), ids = Set<UUID>(), bytes = 0
        let ordered = items.filter { $0.payload.valid && ($0.pinned || retentionDays == nil || now.timeIntervalSince($0.copiedAt) <= Double(retentionDays!) * 86400) && $0.copiedAt <= now.addingTimeInterval(60) }
            .sorted { $0.pinned != $1.pinned ? $0.pinned : $0.copiedAt > $1.copiedAt }
        var accepted: [ClipboardEntry] = []
        for item in ordered {
            guard accepted.count < min(maxEntries, max(1, limit)), !ids.contains(item.id), !unique.contains(item.payload.fingerprint), bytes + item.payload.byteCount <= maxBytes else { continue }
            ids.insert(item.id); unique.insert(item.payload.fingerprint); bytes += item.payload.byteCount; accepted.append(item)
        }
        return accepted.sorted { $0.copiedAt > $1.copiedAt }
    }
    private func bounded(_ items: [ClipboardEntry]) -> [ClipboardEntry] {
        Self.bounded(items, now: now(), limit: historyLimit, retentionDays: cleanup == .afterDays ? retentionDays : nil)
    }
    private func prune() {
        let next = bounded(entries)
        if next != entries { entries = next; save() }
    }
    func handleCleanupEvent(_ event: ClipboardCleanup) {
        guard loaded, cleanup == event, event != .afterDays else { return }
        generation += 1; lastCount = nil; entries = []; save(immediate: true); status = "History cleared"
    }
    nonisolated static func systemBootTime() -> TimeInterval {
        var value = timeval(), length = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &length, nil, 0) == 0 else { return 0 }
        return TimeInterval(value.tv_sec)
    }
    private func checkLid() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard let closed = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool else { return }
        if closed && !lidWasClosed { handleCleanupEvent(.lidClose) }
        lidWasClosed = closed
    }
    func filtered(query: String, kind: ClipboardKind? = nil, pinnedOnly: Bool = false) -> [ClipboardEntry] {
        entries.filter { item in
            (kind == nil || kind == item.payload.kind) && (!pinnedOnly || item.pinned) &&
            (query.isEmpty || ([item.payload.title, item.payload.text, item.sourceName] + item.payload.files.map(\.lastPathComponent)).contains { $0.localizedStandardContains(query) })
        }.sorted { $0.pinned != $1.pinned ? $0.pinned : $0.copiedAt > $1.copiedAt }
    }
    func togglePin(_ id: UUID) { guard let index = entries.firstIndex(where: { $0.id == id }) else { return }; entries[index].pinned.toggle(); save() }
    func remove(_ id: UUID) { entries.removeAll { $0.id == id }; save() }
    func clear() { entries = []; save(); status = "History cleared" }
    private func isExcluded(_ bundle: String) -> Bool { excludedApps.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.contains(bundle) }
    private func save(immediate: Bool = false) {
        revision += 1; let version = revision, snapshot = entries, storage = storage
        persistence?.cancel()
        persistence = Task { @MainActor [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            do { try await storage.save(snapshot, revision: version) }
            catch { self?.status = "History changed, but could not be saved on this Mac" }
        }
    }
    func flush() async { await persistence?.value }
    func preparePasteTarget() {
        guard monitorsSystem else { return }
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { pasteTarget = front }
    }
    func copy(_ item: ClipboardEntry) async -> Bool {
        guard !copying else { return false }
        copying = true; defer { copying = false }
        generation += 1
        guard let count = await access.write(item.payload) else { lastCount = nil; status = "Could not copy. Try again."; return false }
        lastCount = count; status = "Copied — paste with ⌘V"; return true
    }
    var canPaste: Bool { monitorsSystem && AXIsProcessTrusted() && pasteTarget?.isTerminated == false }
    func paste(_ item: ClipboardEntry, dismiss: () -> Void) async {
        let target = pasteTarget
        guard await copy(item) else { return }
        let writtenCount = lastCount
        guard monitorsSystem, AXIsProcessTrusted(), let target, !target.isTerminated else { status = "Copied. Use ⌘V, or allow Accessibility for direct paste."; return }
        dismiss(); target.activate()
        try? await Task.sleep(for: .milliseconds(180))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else { status = "Copied. Select your destination and press ⌘V."; return }
        guard let current = await access.read(after: writtenCount, includeMedia: false), current.changeCount == writtenCount else { status = "Clipboard changed. Copy your selection again before pasting."; return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier, !target.isTerminated else { status = "Copied. Select your destination and press ⌘V."; return }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true), up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        guard let down, let up else { status = "Copied. Press ⌘V in your destination."; return }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        status = "Paste requested"
    }
    func requestPasteAccess() {
        guard monitorsSystem else { return }
        let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        status = trusted ? "Direct paste is ready" : "Allow Sieghart in Accessibility, then return here"
    }
    func openPasteAccess() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    private func observeSession() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.didWakeNotification, NSWorkspace.didActivateApplicationNotification, NSWorkspace.willPowerOffNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let bundle = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWorkspace.willPowerOffNotification { self.handleCleanupEvent(.shutdown) }
                    else if name == NSWorkspace.willSleepNotification {
                        self.checkLid(); self.sessionSuspended = true; self.resetCapture()
                    }
                    else if name == NSWorkspace.didActivateApplicationNotification {
                        self.preparePasteTarget()
                        if self.isExcluded(bundle) { self.excludedSinceRead = true }
                    } else { self.sessionSuspended = name == NSWorkspace.sessionDidResignActiveNotification || name == NSWorkspace.willSleepNotification; self.resetCapture() }
                }
            })
        }
    }
}
