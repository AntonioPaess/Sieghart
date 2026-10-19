import AppKit
import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.clipboard, .logic))
  struct CompanionEntranceTests {
    @Test("G12.07 240 Hz continuity, bounded poses and immediate reduced motion")
    func arrival() throws {
      for t in stride(from: 0.0, through: 3.5, by: 1.0 / 240) {
        let a = CompanionEntranceMotion.sample(elapsed: t)
        let b = CompanionEntranceMotion.sample(elapsed: t + 1.0 / 240)
        #expect(a.opacity >= 0 && a.opacity <= 1 && a.eyeOpen >= 0.08 && a.eyeOpen <= 1)
        #expect(abs(a.offset - b.offset) < 0.022 && abs(a.scaleX - b.scaleX) < 0.01)
        #expect(a.scaleX >= 0.8 && a.scaleX < 1.1 && a.scaleY >= 0.8 && a.scaleY < 1.1)
      }
      let arrival = CompanionEntranceMotion.sample(elapsed: 4)
      #expect(
        abs(arrival.offset) < 0.001 && abs(arrival.scaleX - 1) < 0.001 && arrival.eyeOpen == 1)
      #expect(CompanionEntranceMotion.sample(elapsed: 0).opacity == 0)
      #expect(
        CompanionEntranceMotion.sample(elapsed: 0, reducedMotion: true) == CompanionEntranceMotion()
      )
    }

  }
}
