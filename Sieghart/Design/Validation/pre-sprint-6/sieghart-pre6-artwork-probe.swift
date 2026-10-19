
// Disposable validation probe, never part of the repository target.
@Suite(.serialized) @MainActor struct PreS6EvidenceProbe {
    @Test func a_deliberateFailure() { #expect(Bool(false), "Expected negative control") }
    @Test func b_cacheRestorationInBothOrders() throws {
        let menu = MacContractsTests.CompanionMenuImageTests()
        let raster = MacContractsTests.CompanionRasterLifecycleTests()
        for order in [CompanionAvatar.allCases, Array(CompanionAvatar.allCases.reversed())] {
            let saved = CompanionAvatar.allCases.map { (NSImage.Name("Companion-\($0.rawValue)"), NSImage(named: "Companion-\($0.rawValue)")) }
            try raster.retinaRaster()
            for avatar in order { try menu.menuImage(avatar) }
            try raster.retinaRaster()
            for (name, image) in saved {
                if let image { #expect(NSImage(named: name) === image) }
                else { #expect(NSImage(named: name) == nil) }
            }
        }
    }
}
