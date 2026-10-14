import XCTest

final class BreakwaterUITests: XCTestCase {
    var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-preferences", "--mute-audio"]
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
        app.terminate(); app.launchArguments = ["--mute-audio"]; app.launch()
        XCTAssertTrue(app.buttons["pad_2"].waitForExistence(timeout: 20))
        waitUntilReady()
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
    func test05RevisedLibrary() {
        let pages: [(String, Int, Int)] = [
            ("A Safe Balm", 18, 74),
            ("L'abeille", 18, 119),
            ("Sobaka", 18, 221),
            ("Penguin", 18, 179),
            ("Biotic Discussion", 18, 222),
            ("Can You See?", 12, 257),
            ("Sniper Growl", 12, 269),
            ("Nashira", 12, 281),
            ("Dawn At Dawn", 12, 293),
            ("Swingland Hit", 6, 299)
        ]
        for (index, page) in pages.enumerated() {
            let (name, count, pad) = page
            app.buttons["songMenu"].tap()
            let song = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + " ·")).firstMatch
            // The system menu lazily creates rows below the visible song list.
            for _ in 0..<4 {
                if song.exists { break }
                app.collectionViews.firstMatch.swipeUp()
            }
            XCTAssertTrue(song.exists, "Missing song: \(name)")
            song.tap()
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
}
