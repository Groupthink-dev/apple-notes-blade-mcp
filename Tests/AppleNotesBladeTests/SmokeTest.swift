import XCTest
@testable import AppleNotesBlade

final class SmokeTest: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(AppleNotesBlade.version.isEmpty)
    }
}
