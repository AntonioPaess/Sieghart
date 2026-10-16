import Foundation

/// Pure injected inputs only: no model, code-signature, account or network access.
enum AppleChatEligibilityChecks {
    static func run() {
        for macOSMajor in [-1, 0, 14, 25, 26] {
            for mode in AppleChatMode.allCases {
                for entitled in [false, true] {
                    let result = AppleChatEligibility.prerequisite(
                        for: mode, macOSMajor: macOSMajor, hasPCCEntitlement: entitled)
                    precondition(result?.available == false)
                    precondition(result?.reason?.contains("macOS 27") == true)
                }
            }
        }

        for macOSMajor in [27, 28] {
            for entitled in [false, true] {
                // An offline model must never be blocked on a cloud entitlement.
                precondition(AppleChatEligibility.prerequisite(
                    for: .onDevice, macOSMajor: macOSMajor, hasPCCEntitlement: entitled) == nil)
            }
            let missing = AppleChatEligibility.prerequisite(
                for: .privateCloudThinking, macOSMajor: macOSMajor, hasPCCEntitlement: false)
            precondition(missing?.available == false)
            precondition(missing?.reason?.contains("approved Private Cloud Compute entitlement") == true)
            // nil means the engine must check live model availability; never `.available`.
            precondition(AppleChatEligibility.prerequisite(
                for: .privateCloudThinking, macOSMajor: macOSMajor, hasPCCEntitlement: true) == nil)
        }
        print("PASS: new Apple model OS requirements and managed PCC entitlement prerequisites. Pure inputs; no model, signature, account or network access.")
    }
}
