import XCTest

final class BreakwaterUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-preferences"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["pad_0"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["transport"].waitForExistence(timeout: 20))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: app.buttons["transport"])
        waitForExpectations(timeout: 20)
    }
    func waitForValue(_ id: String, _ value: String, timeout: TimeInterval = 8) {
        expectation(for: NSPredicate(format: "value CONTAINS %@", value), evaluatedWith: app.buttons[id])
        waitForExpectations(timeout: timeout)
    }
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func test01LaunchQueueAndDropdown() {
        app.buttons["pad_5"].tap()
        waitForValue("pad_5", "Playing")
        app.buttons["pad_8"].tap()
        // Musical quantization is measured sample-accurately in AudioCoreTests;
        // this integration test checks the queue reaches the live renderer.
        waitForValue("pad_8", "Playing")
        app.buttons["pad_13"].tap()
        capture("tablet-landscape")
        app.buttons["songMenu"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Malanga'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["pad_30"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
        app.buttons["pad_30"].tap()
        waitForValue("pad_30", "Playing")
        app.segmentedControls.buttons["Slice"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Slice"].isSelected)
        app.buttons["transport"].tap()
        expectation(for: NSPredicate(format: "label == 'Play'"), evaluatedWith: app.buttons["transport"])
        waitForExpectations(timeout: 3)
    }
    func test02ExclusionsPersistAndRestore() {
        app.buttons["editPads"].tap()
        app.buttons["pad_2"].tap()
        waitForValue("pad_2", "Excluded")
        app.buttons["editPads"].tap()
        XCTAssertFalse(app.buttons["pad_2"].isEnabled)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(app.buttons["pad_2"].waitForExistence(timeout: 20))
        waitForValue("pad_2", "Excluded")
        app.buttons["editPads"].tap()
        app.buttons["pad_2"].tap()
        waitForValue("pad_2", "Ready")
    }
    func test03DragCycleAndPortrait() {
        app.buttons["pad_0"].press(forDuration: 0.2, thenDragTo: app.buttons["pad_2"])
        waitForValue("pad_0", "Playing")
        XCTAssertTrue((app.buttons["pad_2"].value as? String ?? "").contains("Cycle"))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["pad_29"].isHittable)
        capture("tablet-portrait")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.switches["externalClock"].waitForExistence(timeout: 3))
        capture("tablet-settings")
        app.buttons["settingsDone"].tap()
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
    }
    func test04AppearanceCapture() {
        app.buttons["pad_5"].tap()
        waitForValue("pad_5", "Playing")
        capture("tablet-appearance")
        XCTAssertTrue(app.buttons["settings"].isHittable)
        XCTAssertTrue(app.buttons["pad_29"].isHittable)
    }
}
