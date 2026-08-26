import XCTest

@testable import FoldscaleCore

final class FoldscaleCoreTests: XCTestCase {
    func testVersionIsExposed() {
        XCTAssertFalse(FoldscaleCore.version.isEmpty)
    }
}
