import XCTest
@testable import ListCore

final class SanityTests: XCTestCase {
    func testModuleLinks() {
        XCTAssertTrue(listCoreLinked)
    }
}
