import AppKit
import Foundation
import Testing

extension MacContractsTests {
  @Suite(.tags(.clipboard, .isolated)) @MainActor
  struct IslandToolPreferenceTests {
    @Test("G12.05 six rails, swaps, repeated none, ten tools and duplicate recovery persist")
    func tools() throws {
      let fixture = try TestDefaults()
      let defaults = fixture.value
      defer { fixture.cleanup() }
      let prefs = CompanionPreferences(defaults: defaults)
      #expect(prefs.railActions.count == 6 && prefs.railActions.contains(.clipboard))
      prefs.setRail(.clipboard, at: 4)
      #expect(prefs.railActions[4] == .clipboard && Set(prefs.railActions).count == 6)
      prefs.setRail(.none, at: 0)
      prefs.setRail(.none, at: 1)
      #expect(prefs.railActions[0] == .none && prefs.railActions[1] == .none)
      prefs.applyRailPreset(.work)
      #expect(CompanionPreferences(defaults: defaults).railActions == IslandRailPreset.work.actions)
      #expect(
        prefs.toolActions == IslandToolAction.defaultSelection && prefs.toolActions.count == 10)
      prefs.setTool(.preferences, at: 9)
      #expect(prefs.toolActions[9] == .preferences && !prefs.toolActions.contains(.displayPower))
      prefs.setTool(.calendar, at: 0)
      #expect(prefs.toolActions[0] == .calendar && prefs.toolActions[5] == .companion)
      prefs.moveTool(from: 0, to: 1)
      #expect(prefs.toolActions[1] == .calendar && Set(prefs.toolActions).count == 10)
      #expect(CompanionPreferences(defaults: defaults).toolActions == prefs.toolActions)
      prefs.resetTools()
      #expect(prefs.toolActions == IslandToolAction.defaultSelection)
      defaults.set(
        Array(repeating: IslandToolAction.calendar.rawValue, count: 10), forKey: "island.tools")
      #expect(
        CompanionPreferences(defaults: defaults).toolActions == IslandToolAction.defaultSelection)
    }

  }
}
