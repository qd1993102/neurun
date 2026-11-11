import XCTest

final class NeurunUITests: XCTestCase {
    @MainActor
    func testLaunchShowsHelloWorld() {
        let app = XCUIApplication()
        app.launch()

        let greeting = app.staticTexts["hello-world"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 5))
        XCTAssertEqual(greeting.label, "Hello, world!")
    }
}
