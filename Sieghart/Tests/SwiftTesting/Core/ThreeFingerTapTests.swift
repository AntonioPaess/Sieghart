import Foundation
import Testing

extension LogicTests {
  @Suite(.tags(.middleClick, .logic))
  struct ThreeFingerTapTests {
    @Test("G13.01 three fingers, debounce, duration, motion and staggered contacts")
    func threeFingerTap() throws {
      let contacts = (0..<3).map {
        TrackpadContact(id: Int32($0), x: 0.2 + Double($0) * 0.15, y: 0.5)
      }
      var tap = ThreeFingerTap()
      let observed1 = tap.consume(contacts, at: 0)
      let observed2 = tap.consume([], at: 0.12)
      #expect(!observed1)
      #expect(observed2)
      let observed3 = tap.consume(contacts, at: 0.2)
      let observed4 = tap.consume([], at: 0.25)
      #expect(!observed3)
      #expect(!observed4)  // debounce
      let observed5 = tap.consume(Array(contacts.prefix(2)), at: 1)
      let observed6 = tap.consume([], at: 1.1)
      #expect(!observed5)
      #expect(!observed6)
      let observed7 = tap.consume(contacts, at: 2)
      let observed8 = tap.consume([], at: 2.4)
      #expect(!observed7)
      #expect(!observed8)
      let observed9 = tap.consume(contacts, at: 3)
      let observed10 = tap.consume(
        contacts.map { TrackpadContact(id: $0.id, x: $0.x + 0.1, y: $0.y) }, at: 3.1)
      let observed11 = tap.consume([], at: 3.2)
      #expect(!observed9)
      #expect(!observed10)
      #expect(!observed11)
      let observed12 = tap.consume(contacts + [TrackpadContact(id: 9, x: 0.8, y: 0.5)], at: 4)
      let observed13 = tap.consume([], at: 4.1)
      #expect(!observed12)
      #expect(!observed13)
      let observed14 = tap.consume(Array(contacts.prefix(1)), at: 5)
      let observed15 = tap.consume(contacts, at: 5.06)
      let observed16 = tap.consume(Array(contacts.prefix(2)), at: 5.08)
      let observed17 = tap.consume([], at: 5.15)
      #expect(!observed14)
      #expect(!observed15)
      #expect(!observed16)
      #expect(observed17)
    }

  }
}
