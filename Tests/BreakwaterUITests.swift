import XCTest

final class BreakwaterUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-preferences", "--mute-audio"]
        if name.contains("MIDI") { app.launchArguments.append("--test-midi-clock") }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["pad_0"].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["transport"])
        waitForExpectations(timeout: 30)
    }
    func waitForValue(_ id: String, _ value: String, timeout: TimeInterval = 15) {
        expectation(for: NSPredicate(format: "value CONTAINS %@", value), evaluatedWith: app.buttons[id])
        waitForExpectations(timeout: timeout)
    }
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func selectFolder(_ id: String) {
        let folder = app.buttons["song_\(id)"]
        let library = app.scrollViews["songList"]
        for _ in 0..<12 where !folder.isHittable { library.swipeUp() }
        XCTAssertTrue(folder.isHittable, "Folder \(id) must be reachable by scrolling")
        folder.tap()
    }
    func testTimelineLayersAndIndependentSound() {
        app.buttons["showSound"].tap()
        XCTAssertFalse(app.segmentedControls["filterMode"].buttons["LPF"].isEnabled, "A clip must be selected before editing its filter")
        XCTAssertTrue(app.segmentedControls["masterFilterMode"].buttons["LPF"].isEnabled, "The master filter remains available without a clip")
        app.buttons["showSound"].tap()
        app.buttons["pad_0"].tap()
        XCTAssertTrue(app.buttons["clip_1"].waitForExistence(timeout: 15))
        waitForValue("clip_1", "Playing")
        XCTAssertEqual(app.buttons["pad_0"].value as? String, "Ready")
        app.buttons["pad_1"].tap()
        XCTAssertTrue(app.buttons["clip_2"].waitForExistence(timeout: 10))
        app.buttons["pad_2"].press(forDuration: 0.8, thenDragTo: app.buttons["clip_1"])
        XCTAssertTrue(app.buttons["clip_3"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["clip_3"].label.contains("step 1"), "Dragging onto a clip should add a layer to its step")
        app.buttons["clip_1"].tap()
        XCTAssertTrue(app.buttons["part_0"].waitForExistence(timeout: 8))
        XCTAssertGreaterThan(app.otherElements["soundTray"].frame.minY, app.buttons["clip_1"].frame.maxY, "Sound should sit below the timeline")
        app.buttons["part_0"].tap(); waitForValue("part_0", "Off")
        let filter = app.segmentedControls["filterMode"]
        let devices = app.scrollViews["soundDevices"]
        for _ in 0..<4 where !filter.buttons["LPF"].isHittable { devices.swipeLeft() }
        XCTAssertTrue(filter.buttons["LPF"].isHittable)
        filter.buttons["LPF"].tap()
        XCTAssertTrue(filter.buttons["LPF"].isSelected)
        app.buttons["clip_3"].tap(); waitForValue("part_0", "On")
        XCTAssertTrue(filter.buttons["Off"].isSelected)
        app.buttons["clip_1"].tap(); waitForValue("part_0", "Off")
        XCTAssertTrue(filter.buttons["LPF"].isSelected)
        XCTAssertTrue(app.segmentedControls["masterFilterMode"].exists)
        XCTAssertEqual(app.sliders["Master filter cutoff"].value as? String, "1.2 kHz")
        capture("timeline-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["transport"].isHittable)
        XCTAssertTrue(app.buttons["nudgeEarlier"].isHittable)
        for _ in 0..<4 where !app.buttons["part_0"].isHittable { devices.swipeRight() }
        XCTAssertTrue(app.buttons["part_0"].isHittable, "Parts remain reachable in portrait")
        for _ in 0..<4 where !app.segmentedControls["masterFilterMode"].buttons["LPF"].isHittable { devices.swipeLeft() }
        XCTAssertTrue(app.segmentedControls["masterFilterMode"].buttons["LPF"].isHittable, "Master filter remains reachable in portrait")
        capture("timeline-portrait")
    }
    func testExclusionsPersistAndRestore() {
        app.buttons["editPads"].tap(); app.buttons["pad_2"].tap(); waitForValue("pad_2", "Excluded")
        app.buttons["editPads"].tap(); XCTAssertFalse(app.buttons["pad_2"].isEnabled)
        app.terminate(); app.launchArguments = ["--mute-audio"]; app.launch()
        XCTAssertTrue(app.buttons["pad_2"].waitForExistence(timeout: 30)); waitForValue("pad_2", "Excluded")
        app.buttons["editPads"].tap(); app.buttons["pad_2"].tap(); waitForValue("pad_2", "Ready")
    }
    func testInsertionEdgesAndPlacementMenu() {
        app.buttons["pad_0"].tap(); app.buttons["pad_1"].tap()
        XCTAssertTrue(app.buttons["clip_2"].waitForExistence(timeout: 15))
        let source = app.buttons["pad_2"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let leftEdge = app.buttons["clip_1"].coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        source.press(forDuration: 0.8, thenDragTo: leftEdge)
        XCTAssertTrue(app.buttons["clip_3"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["clip_3"].label.contains("step 1"), "Dropping near the leading edge inserts a step")
        app.buttons["placementMenu"].tap(); app.buttons["Insert before selected step"].tap(); app.buttons["pad_3"].tap()
        XCTAssertTrue(app.buttons["clip_4"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["clip_4"].label.contains("step 1"))
        app.buttons["placementMenu"].tap(); app.buttons["Insert after selected step"].tap(); app.buttons["pad_4"].tap()
        XCTAssertTrue(app.buttons["clip_5"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["clip_5"].label.contains("step 2"))
        app.buttons["placementMenu"].tap(); app.buttons["Add as layer"].tap(); app.buttons["pad_5"].tap()
        XCTAssertTrue(app.buttons["clip_6"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["clip_6"].label.contains("step 2"))
    }
    func testFolderNavigationAndSourceTempo() {
        app.buttons["useSourceTempo"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS '105.0'"), evaluatedWith: app.buttons["tempo"])
        waitForExpectations(timeout: 10)
        app.buttons["song_sg"].tap()
        selectFolder("ml")
        XCTAssertTrue(app.buttons["pad_30"].waitForExistence(timeout: 5))
        app.buttons["useSourceTempo"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS '150.0'"), evaluatedWith: app.buttons["tempo"])
        waitForExpectations(timeout: 10)
        app.buttons["song_ml"].tap()
        selectFolder("sh")
        XCTAssertTrue(app.buttons["pad_294"].waitForExistence(timeout: 5))
    }
    func testMIDIClockAndFolderBrowsing() {
        expectation(for: NSPredicate(format: "label CONTAINS 'LOCKED'"), evaluatedWith: app.buttons["clockStatus"])
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.buttons["useSourceTempo"].isEnabled)
        app.buttons["pad_0"].tap(); XCTAssertTrue(app.buttons["clip_1"].waitForExistence(timeout: 15))
        waitForValue("clip_1", "Playing")
        app.buttons["song_sg"].tap(); selectFolder("sh")
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
        XCTAssertTrue(app.buttons["pad_294"].waitForExistence(timeout: 5))
        app.buttons["pad_294"].tap(); XCTAssertTrue(app.buttons["clip_2"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
        app.buttons["nudgeEarlier"].tap(); app.buttons["nudgeLater"].tap()
        app.buttons["clip_2"].tap(); XCTAssertTrue(app.buttons["part_0"].waitForExistence(timeout: 10))
        app.buttons["part_0"].tap(); waitForValue("part_0", "Off")
        XCTAssertTrue(app.buttons["clockStatus"].label.contains("LOCKED"))
    }
}
