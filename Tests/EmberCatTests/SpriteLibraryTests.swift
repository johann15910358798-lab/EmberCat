import AppKit
import XCTest
@testable import EmberCat

final class SpriteLibraryTests: XCTestCase {
    @MainActor
    func testApplicationResourceContract() {
        XCTAssertTrue(checkMenuBarResources())
    }
}
