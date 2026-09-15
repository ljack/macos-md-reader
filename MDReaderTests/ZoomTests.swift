import XCTest
@testable import MDReader

final class ZoomTests: XCTestCase {
    func testStepUpAndDownWalkThePresets() {
        XCTAssertEqual(Zoom.stepped(from: 1.0, +1), 1.1)
        XCTAssertEqual(Zoom.stepped(from: 1.0, -1), 0.9)
        XCTAssertEqual(Zoom.stepped(from: 0.9, -1), 0.8)
    }

    func testStepClampsAtTheEnds() {
        XCTAssertEqual(Zoom.stepped(from: Zoom.minimum, -1), Zoom.minimum)
        XCTAssertEqual(Zoom.stepped(from: Zoom.maximum, +1), Zoom.maximum)
        XCTAssertEqual(Zoom.stepped(from: 9.0, +1), Zoom.maximum)
        XCTAssertEqual(Zoom.stepped(from: 0.01, -1), Zoom.minimum)
    }

    func testStepFromBetweenPresetsSnapsToNeighbour() {
        // After a pinch the scale can sit anywhere; ⌘- must still shrink and ⌘+ still grow.
        XCTAssertEqual(Zoom.stepped(from: 0.73, -1), 0.7)
        XCTAssertEqual(Zoom.stepped(from: 0.73, +1), 0.8)
        XCTAssertEqual(Zoom.stepped(from: 1.3, -1), 1.25)
        XCTAssertEqual(Zoom.stepped(from: 1.3, +1), 1.5)
    }

    func testPinchShrinksAndGrowsWithinBounds() {
        XCTAssertEqual(Zoom.pinched(from: 1.0, by: -0.1), 0.9, accuracy: 0.0001)
        XCTAssertEqual(Zoom.pinched(from: 1.0, by: 0.25), 1.25, accuracy: 0.0001)
        XCTAssertEqual(Zoom.pinched(from: 0.55, by: -0.5), Zoom.minimum)
        XCTAssertEqual(Zoom.pinched(from: 2.9, by: 0.5), Zoom.maximum)
    }

    func testSetPersistsClampedAndResetReturnsToOne() {
        let saved = UserDefaults.standard.object(forKey: "pageZoom")
        defer { UserDefaults.standard.set(saved, forKey: "pageZoom") }
        Zoom.set(0.2)
        XCTAssertEqual(Zoom.current, Zoom.minimum)
        Zoom.set(0.65)
        XCTAssertEqual(Zoom.current, 0.65, accuracy: 0.0001)
        Zoom.reset()
        XCTAssertEqual(Zoom.current, 1.0)
    }
}
