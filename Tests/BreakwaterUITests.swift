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
        let master = app.segmentedControls["masterFilterMode"]
        XCTAssertTrue(master.buttons["HPF"].isHittable)
        master.buttons["HPF"].tap()
        let masterCutoff = app.sliders["Master filter cutoff"]
        masterCutoff.adjust(toNormalizedSliderPosition: 0.7)
        let chosenCutoff = masterCutoff.value as? String
        app.buttons["pad_0"].tap()
        XCTAssertTrue(app.buttons["clip_1"].waitForExistence(timeout: 15))
        waitForValue("clip_1", "Playing")
        XCTAssertEqual(app.buttons["pad_0"].value as? String, "Ready")
        app.buttons["pad_1"].tap()
        XCTAssertTrue(app.buttons["clip_2"].waitForExistence(timeout: 10))
        app.buttons["pad_2"].press(forDuration: 0.8, thenDragTo: app.buttons["clip_1"])
        XCTAssertTrue(app.buttons["clip_3"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["clip_3"].label.contains("step 1"), "Dragging onto a clip should add a layer to its step")
        let firstLevel = app.sliders["clipLevel_1"], layeredLevel = app.sliders["clipLevel_3"]
        XCTAssertTrue(firstLevel.waitForExistence(timeout: 5))
        XCTAssertTrue(layeredLevel.exists)
        let unchangedLevel = layeredLevel.value as? String
        let top = firstLevel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let bottom = firstLevel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        let firstValue = (firstLevel.value as? String ?? "").replacingOccurrences(of: "%", with: "")
        XCTAssertLessThan(Int(firstValue) ?? 100, 30, "Dragging the vertical fader lowers this clip")
        XCTAssertEqual(layeredLevel.value as? String, unchangedLevel, "Each timeline instance has an independent level")
        let firstPart = app.buttons["clipPart_1_0"], layeredPart = app.buttons["clipPart_3_0"]
        XCTAssertTrue(firstPart.isHittable)
        firstPart.tap(); waitForValue("clipPart_1_0", "Off")
        waitForValue("clipPart_3_0", "On")
        let firstFilter = app.descendants(matching: .any)["clipFilter_1"]
        let layeredFilter = app.descendants(matching: .any)["clipFilter_3"]
        XCTAssertTrue(firstFilter.isHittable)
        let dial = firstFilter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let down = dial.withOffset(CGVector(dx: 0, dy: 45))
        dial.press(forDuration: 0.1, thenDragTo: down)
        expectation(for: NSPredicate(format: "value CONTAINS 'LP'"), evaluatedWith: firstFilter)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(layeredFilter.value as? String, "Off", "Each clip has an independent filter")
        firstFilter.doubleTap()
        expectation(for: NSPredicate(format: "value == 'Off'"), evaluatedWith: firstFilter)
        waitForExpectations(timeout: 5)
        dial.press(forDuration: 0.1, thenDragTo: dial.withOffset(CGVector(dx: 0, dy: -45)))
        expectation(for: NSPredicate(format: "value CONTAINS 'HP'"), evaluatedWith: firstFilter)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(master.buttons["HPF"].isSelected)
        XCTAssertEqual(masterCutoff.value as? String, chosenCutoff)
        capture("timeline-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["transport"].isHittable)
        XCTAssertTrue(app.buttons["nudgeEarlier"].isHittable)
        XCTAssertTrue(firstPart.isHittable)
        XCTAssertTrue(firstFilter.isHittable)
        XCTAssertTrue(master.buttons["HPF"].isHittable)
        capture("timeline-portrait")
    }
    func testCrowdedTimelineControlsScrollable() {
        for index in 0..<8 { app.buttons["pad_\(index)"].tap() }
        let lastPart = app.buttons["clipPart_8_0"]
        XCTAssertTrue(lastPart.waitForExistence(timeout: 15))
        let timeline = app.scrollViews["timelineScroll"]
        for _ in 0..<8 { timeline.swipeLeft() }
        XCTAssertTrue(lastPart.isHittable, "Crowded steps retain touch-sized controls and scroll horizontally")
        lastPart.tap(); waitForValue("clipPart_8_0", "Off")
        XCTAssertTrue(app.sliders["clipLevel_8"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["clipFilter_8"].isHittable)
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
        XCTAssertTrue(app.buttons["clipPart_2_0"].waitForExistence(timeout: 10))
        app.buttons["clipPart_2_0"].tap(); waitForValue("clipPart_2_0", "Off")
        XCTAssertTrue(app.buttons["clockStatus"].label.contains("LOCKED"))
    }
}
