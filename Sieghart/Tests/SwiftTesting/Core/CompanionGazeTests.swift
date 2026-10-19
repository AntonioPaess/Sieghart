import AppKit
import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.clipboard, .logic))
  struct CompanionGazeTests {
    @Test("G12.05 gaze tracks both sides and is neutral at center")
    func gaze() throws {
      let width = CGSize(width: 610, height: 220)
      #expect(CompanionGaze.sample(point: CGPoint(x: 0, y: 110), in: width).width == -4)
      #expect(CompanionGaze.sample(point: CGPoint(x: 610, y: 110), in: width).width == 4)
      #expect(CompanionGaze.sample(point: CGPoint(x: 305, y: 110), in: width) == .zero)
    }

  }
}
