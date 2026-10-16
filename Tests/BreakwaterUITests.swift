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
    func testStacksAndIndependentSound() {
        let master = app.descendants(matching: .any)["masterFilter"]
        XCTAssertTrue(master.isHittable)
        let masterDial = master.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        masterDial.press(forDuration: 0.1, thenDragTo: masterDial.withOffset(CGVector(dx: 0, dy: 45)))
        expectation(for: NSPredicate(format: "value CONTAINS 'LP'"), evaluatedWith: master)
        waitForExpectations(timeout: 5)
        master.doubleTap()
        expectation(for: NSPredicate(format: "value == 'Off'"), evaluatedWith: master)
        waitForExpectations(timeout: 5)
        masterDial.press(forDuration: 0.1, thenDragTo: masterDial.withOffset(CGVector(dx: 0, dy: -45)))
        expectation(for: NSPredicate(format: "value CONTAINS 'HP'"), evaluatedWith: master)
        waitForExpectations(timeout: 5)
        let chosenMaster = master.value as? String
        app.buttons["padAddA_0"].tap()
        XCTAssertTrue(app.buttons["clip_1"].waitForExistence(timeout: 15))
        waitForValue("clip_1", "Playing")
        XCTAssertEqual(app.buttons["pad_0"].value as? String, "Ready")
        app.buttons["padAddB_1"].tap()
        XCTAssertTrue(app.buttons["clip_2"].waitForExistence(timeout: 10))
        app.buttons["pad_2"].press(forDuration: 0.8, thenDragTo: app.buttons["clip_1"])
        XCTAssertTrue(app.buttons["clip_3"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["clip_3"].label.contains("side A"), "Dragging onto a clip should add it to the same side")
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
        XCTAssertEqual(master.value as? String, chosenMaster, "Changing a clip filter must not change the master")
        capture("stacks-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["transport"].isHittable)
        XCTAssertTrue(app.buttons["nudgeEarlier"].isHittable)
        XCTAssertTrue(firstPart.isHittable)
        XCTAssertTrue(firstFilter.isHittable)
        XCTAssertTrue(master.isHittable)
        capture("stacks-portrait")
    }
    func testCrowdedStackControlsScrollable() {
        app.buttons["Fade to side B"].tap()
        for index in 0..<8 { app.buttons["padAddA_\(index)"].tap() }
        XCTAssertFalse(app.buttons["padAddA_0"].isEnabled)
        XCTAssertTrue(app.buttons["padAddB_0"].isEnabled)
        let lastPart = app.buttons["clipPart_8_0"]
        XCTAssertTrue(lastPart.waitForExistence(timeout: 15))
        let timeline = app.scrollViews["timelineScroll"]
        for _ in 0..<8 where !lastPart.isHittable { timeline.swipeUp() }
        XCTAssertTrue(lastPart.isHittable, "Crowded stacks retain touch-sized controls and scroll vertically")
        lastPart.tap(); waitForValue("clipPart_8_0", "Off")
        XCTAssertTrue(app.sliders["clipLevel_8"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["clipFilter_8"].isHittable)
    }
    func testExclusionsPersistAndRestore() {
        app.buttons["editPads"].tap(); app.buttons["pad_2"].tap(); waitForValue("pad_2", "Excluded")
        app.buttons["editPads"].tap()
        XCTAssertFalse(app.buttons["padAddA_2"].isEnabled)
        XCTAssertFalse(app.buttons["padAddB_2"].isEnabled)
        app.terminate(); app.launchArguments = ["--mute-audio"]; app.launch()
        XCTAssertTrue(app.buttons["pad_2"].waitForExistence(timeout: 30)); waitForValue("pad_2", "Excluded")
        app.buttons["editPads"].tap(); app.buttons["pad_2"].tap(); waitForValue("pad_2", "Ready")
    }
    func testExplicitSidePlacementAndAllPartsDefaultOn() {
        app.buttons["pad_0"].tap()
        XCTAssertFalse(app.buttons["clip_1"].exists, "Tapping the preview must not add a loop")
        app.buttons["Fade to side A"].tap(); app.buttons["padAddA_0"].tap()
        app.buttons["Fade to side B"].tap(); app.buttons["padAddB_1"].tap()
        XCTAssertTrue(app.buttons["clip_2"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["clip_1"].label.contains("side A"))
        XCTAssertTrue(app.buttons["clip_2"].label.contains("side B"))
        app.buttons["clipPart_1_0"].tap(); waitForValue("clipPart_1_0", "Off")
        app.buttons["Fade to side A"].tap(); app.buttons["padAddA_2"].tap()
        XCTAssertTrue(app.buttons["clip_3"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["clip_3"].label.contains("side A"))
        for part in 0..<4 { waitForValue("clipPart_3_\(part)", "On") }
        app.buttons["Fade to side B"].tap(); app.buttons["padAddB_3"].tap()
        XCTAssertTrue(app.buttons["clip_4"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["clip_4"].label.contains("side B"))
        XCTAssertTrue(app.sliders["crossfader"].exists)
    }
    func testFolderNavigationAndManualTempo() {
        XCTAssertFalse(app.buttons["useSourceTempo"].exists)
        let originalTempo = app.buttons["tempo"].label
        app.buttons["song_sg"].tap()
        selectFolder("ml")
        XCTAssertTrue(app.buttons["pad_30"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tempo"].label, originalTempo, "Browsing must not change the playback tempo")
        app.buttons["tempo"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["song_ml"].tap()
        selectFolder("sh")
        XCTAssertTrue(app.buttons["pad_294"].waitForExistence(timeout: 5))
    }
    func testMIDIClockAndFolderBrowsing() {
        expectation(for: NSPredicate(format: "label CONTAINS 'LOCKED'"), evaluatedWith: app.buttons["clockStatus"])
        waitForExpectations(timeout: 15)
        app.buttons["padAddA_0"].tap(); XCTAssertTrue(app.buttons["clip_1"].waitForExistence(timeout: 15))
        waitForValue("clip_1", "Playing")
        app.buttons["song_sg"].tap(); selectFolder("sh")
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
        XCTAssertTrue(app.buttons["pad_294"].waitForExistence(timeout: 5))
        app.buttons["padAddB_294"].tap(); XCTAssertTrue(app.buttons["clip_2"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
        app.buttons["nudgeEarlier"].tap(); app.buttons["nudgeLater"].tap()
        XCTAssertTrue(app.buttons["clipPart_2_0"].waitForExistence(timeout: 10))
        app.buttons["clipPart_2_0"].tap(); waitForValue("clipPart_2_0", "Off")
        XCTAssertTrue(app.buttons["clockStatus"].label.contains("LOCKED"))
    }
}
