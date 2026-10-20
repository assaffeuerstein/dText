import XCTest
import AppKit

final class dTextUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testCreateAndFindSnippet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["newSnippetButton"].click()
        let title = app.textFields["snippetTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Test signature")
        let abbreviation = app.textFields["snippetAbbreviation"]
        abbreviation.click()
        abbreviation.typeText(";test")
        let body = app.textViews["snippetBody"]
        body.click()
        body.typeText("Made with dText")
        let search = app.textFields["snippetSearch"]
        search.click()
        search.typeText("Test signature")
        XCTAssertTrue(app.staticTexts["Test signature"].firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "dText Library"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testPlaygroundExpandsAndPositionsCursor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        app.buttons["Playground"].click()
        let text = app.textViews["playgroundInput"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.click()
        text.typeText(";log")
        let expanded = NSPredicate(format: "value == %@", "console.log();")
        expectation(for: expanded, evaluatedWith: text)
        waitForExpectations(timeout: 5)
        text.typeText("hello")
        XCTAssertEqual(text.value as? String, "console.log(hello);")
    }

    @MainActor
    func testCloseKeepsMenuBarAliveAndReopenRestoresDock() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let runningApp = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "il.co.druid.dText")
            .max { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) })
        XCTAssertEqual(runningApp.activationPolicy, .regular)

        app.windows["dText"].buttons[XCUIIdentifierCloseWindow].click()
        let hiddenFromDock = NSPredicate { _, _ in runningApp.activationPolicy == .accessory }
        expectation(for: hiddenFromDock, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(runningApp.isTerminated)
        XCTAssertFalse(app.windows["dText"].exists)

        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.click()
        app.menuItems["Open dText"].click()
        XCTAssertTrue(app.windows["dText"].waitForExistence(timeout: 5))
        XCTAssertEqual(runningApp.activationPolicy, .regular)

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.checkBoxes["openAtLogin"].waitForExistence(timeout: 5))
    }
}
