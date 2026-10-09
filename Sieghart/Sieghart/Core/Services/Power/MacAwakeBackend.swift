import AppKit
import Combine
import IOKit.pwr_mgt

enum AwakeMode: String, CaseIterable, Codable { case duration = "Duration", until = "Until", indefinite = "Indefinite" }
struct AwakeRequest: Codable, Equatable {
    var mode = AwakeMode.duration
    var minutes = 30
    var until = Date().addingTimeInterval(3600)
    var keepDisplay = false
    var onlyOnAC = false
    var externalDisplayOnly = false
    var applications: [String] = []
    var restoreOnLaunch = false
    var end: Date? = nil
    func eligible(_ context: AwakeContext) -> Bool {
        (!onlyOnAC || context.onAC) && (!externalDisplayOnly || context.externalDisplay) &&
        (applications.isEmpty || !Set(applications).isDisjoint(with: context.applications))
    }
}
struct AwakeContext { var onAC = true; var externalDisplay = false; var applications: Set<String> = [] }
@MainActor protocol AwakeBackend: AnyObject {
    func context() -> AwakeContext
    func acquire(display: Bool) throws -> UInt32
    func release(_ token: UInt32)
}
struct UtilityFailure: LocalizedError { var message: String; var errorDescription: String? { message } }
@MainActor final class MacAwakeBackend: AwakeBackend {
    func context() -> AwakeContext {
        let power = MacSystemSampler.properties(className: "AppleSmartBattery").first
        return AwakeContext(onAC: power?["ExternalConnected"] as? Bool ?? true,
                            externalDisplay: NSScreen.screens.contains { screen in
                                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                                return CGDisplayIsBuiltin(id.uint32Value) == 0
                            }, applications: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
    }
    func acquire(display: Bool) throws -> UInt32 {
        var token: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithName(display ? kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString : kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Sieghart — user requested keep awake" as CFString, &token)
        guard status == kIOReturnSuccess else { throw UtilityFailure(message: "macOS rejected the keep-awake request (\(status))") }
        return token
    }
    func release(_ token: UInt32) { IOPMAssertionRelease(token) }
}
