import XCTest

final class BreakwaterUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-preferences", "--mute-audio"]
        if name.contains("test06") || name.contains("test09") || name.contains("test10") { app.launchArguments.append("--test-midi-clock") }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["pad_0"].waitForExistence(timeout: 20))
        waitUntilReady()
    }
    func waitUntilReady() {
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
    func selectSong(_ id: String) {
        app.buttons["songMenu"].tap()
        let song = app.buttons["song_\(id)"]
        XCTAssertTrue(app.navigationBars["Songs"].waitForExistence(timeout: 3))
        for _ in 0..<5 {
            if song.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(song.isHittable, "Song \(id) must be reachable by scrolling")
        song.tap()
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
        selectSong("ml")
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
        app.terminate(); app.launchArguments = ["--mute-audio"]; app.launch()
        XCTAssertTrue(app.buttons["pad_2"].waitForExistence(timeout: 20))
        waitUntilReady()
        waitForValue("pad_2", "Excluded")
        app.buttons["editPads"].tap()
        app.buttons["pad_2"].tap()
        waitForValue("pad_2", "Ready")
    }
    func test03DragLayersAndSequenceInPortrait() {
        app.buttons["pad_0"].press(forDuration: 0.7, thenDragTo: app.descendants(matching: .any)["dropStep_0"])
        waitForValue("pad_0", "Playing")
        XCTAssertTrue(app.buttons["clip_1"].waitForExistence(timeout: 4))
        app.buttons["pad_1"].press(forDuration: 0.7, thenDragTo: app.buttons["clip_1"])
        XCTAssertTrue(app.buttons["clip_2"].waitForExistence(timeout: 4))
        app.buttons["pad_2"].press(forDuration: 0.7, thenDragTo: app.descendants(matching: .any)["dropStep_1"])
        XCTAssertTrue(app.buttons["clip_3"].waitForExistence(timeout: 4))
        app.buttons["clip_1"].tap()
        XCTAssertTrue(app.buttons["part_0"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["filterCutoff"].exists)
        app.buttons["part_0"].tap(); waitForValue("part_0", "Off")
        app.buttons["clip_2"].tap(); waitForValue("part_0", "On")
        app.buttons["clip_1"].tap(); waitForValue("part_0", "Off")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["pad_29"].isHittable)
        capture("tablet-portrait")
        app.buttons["settings"].tap()
        XCTAssertTrue(app.switches["externalClock"].waitForExistence(timeout: 3))
        capture("tablet-settings")
        app.buttons["settingsDone"].tap()
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
        app.buttons["transport"].tap()
        expectation(for: NSPredicate(format: "label == 'Play'"), evaluatedWith: app.buttons["transport"])
        waitForExpectations(timeout: 4)
        app.buttons["removeClip_1"].tap()
        XCTAssertFalse(app.buttons["clip_1"].exists)
        XCTAssertEqual(app.buttons["transport"].label, "Play")
        app.buttons["transport"].tap()
        waitForValue("pad_1", "Playing")
    }
    func test04AppearanceCapture() {
        app.buttons["pad_5"].tap()
        waitForValue("pad_5", "Playing")
        capture("tablet-appearance")
        XCTAssertTrue(app.buttons["settings"].isHittable)
        XCTAssertTrue(app.buttons["pad_29"].isHittable)
    }
    func test05RevisedLibrary() {
        let pages: [(String, String, Int, Int)] = [
            ("sb", "A Safe Balm", 18, 74),
            ("ab", "L'abeille", 18, 119),
            ("so", "Sobaka", 18, 221),
            ("pg", "Penguin", 18, 179),
            ("bd", "Biotic Discussion", 18, 222),
            ("cy", "Can You See?", 12, 257),
            ("sn", "Sniper Growl", 12, 269),
            ("na", "Nashira", 12, 281),
            ("dd", "Dawn At Dawn", 12, 293),
            ("sh", "Swingland Hit", 6, 299)
        ]
        for (index, page) in pages.enumerated() {
            let (id, name, count, pad) = page
            selectSong(id)
            XCTAssertTrue(app.buttons["pad_\(pad)"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pad_' ")).count, count)
            if name == "Can You See?" {
                for removed in 240...245 { XCTAssertFalse(app.buttons["pad_\(removed)"].exists) }
                for retained in 246...257 { XCTAssertTrue(app.buttons["pad_\(retained)"].exists) }
            }
            // Exercise sample loading/playback in both modes. Select while stopped
            // so this library check does not race continuous playback UI updates.
            let mode = app.segmentedControls.buttons[index.isMultiple(of: 2) ? "Tape" : "Slice"]
            if !mode.isSelected { mode.tap() }
            expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: mode)
            waitForExpectations(timeout: 5)
            app.buttons["pad_\(pad)"].tap()
            waitForValue("pad_\(pad)", "Playing")
            app.buttons["transport"].tap()
            expectation(for: NSPredicate(format: "label == 'Play'"), evaluatedWith: app.buttons["transport"])
            waitForExpectations(timeout: 5)
        }
        capture("revised-library-swingland-hit")
    }

    func test06SongPickerDuringMIDIClock() {
        let locked = NSPredicate(format: "label CONTAINS 'LOCKED'")
        expectation(for: locked, evaluatedWith: app.buttons["clockStatus"])
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["useSourceTempo"].isEnabled)
        app.buttons["pad_0"].tap()
        waitForValue("pad_0", "Playing")

        // Reach the last song by scrolling, select it once, and queue a pad
        // while the synthetic MIDI clock continues to run.
        selectSong("sh")
        XCTAssertTrue(app.buttons["pad_294"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
        app.buttons["pad_294"].tap()
        waitForValue("pad_294", "Playing")
        selectSong("sg")
        XCTAssertTrue(app.buttons["pad_0"].waitForExistence(timeout: 3))
        app.buttons["pad_0"].tap()
        waitForValue("pad_0", "Playing")
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
    }

    func test10NudgeDuringMIDIClock() {
        expectation(for: NSPredicate(format: "label CONTAINS 'LOCKED'"), evaluatedWith: app.buttons["clockStatus"])
        waitForExpectations(timeout: 10)
        app.buttons["pad_0"].tap()
        waitForValue("pad_0", "Playing")
        let earlier = app.buttons["nudgeEarlier"], later = app.buttons["nudgeLater"]
        XCTAssertTrue(earlier.isHittable && later.isHittable)
        earlier.tap()
        later.press(forDuration: 0.8)
        app.buttons["pad_2"].tap()
        waitForValue("pad_2", "Playing")
        XCTAssertTrue(app.buttons["clockStatus"].label.contains("LOCKED"))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(earlier.isHittable && later.isHittable)
        app.buttons["showSound"].tap()
        XCTAssertTrue(earlier.isHittable && later.isHittable)
        capture("nudge-portrait")
    }

    func test07UseSourceTempo() {
        app.buttons["useSourceTempo"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS '105.0'"), evaluatedWith: app.buttons["tempo"])
        waitForExpectations(timeout: 8)
        selectSong("ml")
        app.buttons["useSourceTempo"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS '150.0'"), evaluatedWith: app.buttons["tempo"])
        waitForExpectations(timeout: 8)
    }

    func test08PartsAndFilterTray() {
        app.buttons["pad_0"].tap()
        waitForValue("pad_0", "Playing")
        let width = app.otherElements["padGrid"].frame.width
        app.buttons["showSound"].tap()
        XCTAssertTrue(app.buttons["part_0"].waitForExistence(timeout: 3))
        XCTAssertLessThan(app.otherElements["padGrid"].frame.width, width)
        app.buttons["All off"].tap()
        waitForValue("part_0", "Off")
        app.buttons["part_0"].tap()
        waitForValue("part_0", "On")
        app.buttons["All on"].tap()
        app.buttons["part_0"].tap()
        waitForValue("part_0", "Off")
        expectation(for: NSPredicate { _, _ in !self.app.staticTexts["partStatus"].exists }, evaluatedWith: nil)
        waitForExpectations(timeout: 20)
        capture("tablet-parts-landscape")
        XCTAssertTrue(app.sliders["filterCutoff"].waitForExistence(timeout: 3))
        app.segmentedControls.buttons["BPF"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["BPF"].isSelected)
        app.sliders["filterCutoff"].adjust(toNormalizedSliderPosition: 0.7)
        XCUIDevice.shared.orientation = .portrait
        capture("tablet-filter-portrait")
        XCTAssertTrue(app.buttons["pad_29"].isHittable)
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
    }

    func test09PartsDuringMIDIClock() {
        expectation(for: NSPredicate(format: "label CONTAINS 'LOCKED'"), evaluatedWith: app.buttons["clockStatus"])
        waitForExpectations(timeout: 10)
        app.buttons["pad_0"].tap(); waitForValue("pad_0", "Playing")
        app.buttons["showSound"].tap(); app.buttons["part_0"].tap()
        expectation(for: NSPredicate { _, _ in !self.app.staticTexts["partStatus"].exists }, evaluatedWith: nil)
        waitForExpectations(timeout: 20)
        app.buttons["pad_1"].tap(); waitForValue("pad_1", "Playing")
        XCTAssertEqual(app.buttons["transport"].label, "Stop")
    }
}
