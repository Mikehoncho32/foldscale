import XCTest

@testable import RadixCore

final class RadixCoreTests: XCTestCase {
    func testVersionIsExposed() {
        XCTAssertFalse(RadixCore.version.isEmpty)
    }
}
