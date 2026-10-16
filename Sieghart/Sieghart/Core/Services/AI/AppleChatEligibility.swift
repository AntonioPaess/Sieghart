import Foundation
import Security

/// Checks prerequisites without loading a model, accessing an account or making a request.
enum AppleChatEligibility {
    static let privateCloudEntitlement = "com.apple.developer.private-cloud-compute"

    /// A nil result only allows the caller to inspect the actual model's availability.
    /// It does not establish that a model is ready or that Apple has granted service access.
    static func prerequisite(for mode: AppleChatMode, macOSMajor: Int,
                             hasPCCEntitlement: Bool) -> LocalChatReadiness? {
        guard macOSMajor >= 27 else {
            return .unavailable("The new Apple Foundation Models require macOS 27 or later. Update macOS to use this chat; the previous model is not used as a fallback.")
        }
        if mode == .privateCloudThinking && !hasPCCEntitlement {
            return .unavailable("Apple Thinking requires an app build signed with Apple's approved Private Cloud Compute entitlement. This build does not include that entitlement. On-device chat remains available on macOS 27 when Apple Intelligence is ready.")
        }
        return nil
    }

    static func currentPrerequisite(for mode: AppleChatMode) -> LocalChatReadiness? {
        let macOSMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        // Avoid inspecting the signature when an OS requirement already rules this out,
        // or when the selected model never uses the managed cloud entitlement.
        let needsEntitlement = macOSMajor >= 27 && mode == .privateCloudThinking
        return prerequisite(for: mode, macOSMajor: macOSMajor,
                            hasPCCEntitlement: needsEntitlement && ownSignatureHasPCCEntitlement())
    }

    private static func ownSignatureHasPCCEntitlement() -> Bool {
        let flags = SecCSFlags(rawValue: 0)
        var runningCode: SecCode?
        guard SecCodeCopySelf(flags, &runningCode) == errSecSuccess,
              let runningCode else { return false }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(runningCode, flags, &staticCode) == errSecSuccess,
              let staticCode else { return false }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                            &information) == errSecSuccess,
              let values = information as? [String: Any],
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let enabled = entitlements[privateCloudEntitlement] as? NSNumber,
              CFGetTypeID(enabled) == CFBooleanGetTypeID() else { return false }
        // This is a fail-closed prerequisite, not a replacement for PCC availability:
        // the OS still validates the managed entitlement and service eligibility.
        return enabled.boolValue
    }
}
